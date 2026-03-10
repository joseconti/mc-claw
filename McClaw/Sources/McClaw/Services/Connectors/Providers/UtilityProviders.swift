import Foundation
import Logging
import McClawKit

// MARK: - Weather Provider (OpenWeatherMap)

struct WeatherProvider: ConnectorProvider {
    static let definitionId = "util.weather"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "current":
            guard let city = params["city"] else { throw ConnectorProviderError.missingParameter("city") }
            data = try await currentWeather(city: city, credentials: credentials)

        case "forecast":
            guard let city = params["city"] else { throw ConnectorProviderError.missingParameter("city") }
            data = try await forecast(city: city, credentials: credentials)

        case "alerts":
            guard let lat = params["lat"] else { throw ConnectorProviderError.missingParameter("lat") }
            guard let lon = params["lon"] else { throw ConnectorProviderError.missingParameter("lon") }
            data = try await alerts(lat: lat, lon: lon, credentials: credentials)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        guard let apiKey = credentials.apiKey, !apiKey.isEmpty else { return false }
        let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?q=London&appid=\(apiKey)&units=metric")!
        let request = URLRequest(url: url)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - API Calls

    private func currentWeather(city: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await weatherGet(
            path: "/data/2.5/weather",
            queryItems: [URLQueryItem(name: "q", value: city), URLQueryItem(name: "units", value: "metric")],
            credentials: credentials
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        return ConnectorsKit.formatCurrentWeather(json)
    }

    private func forecast(city: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await weatherGet(
            path: "/data/2.5/forecast",
            queryItems: [URLQueryItem(name: "q", value: city), URLQueryItem(name: "units", value: "metric")],
            credentials: credentials
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        return ConnectorsKit.formatWeatherForecast(json)
    }

    private func alerts(lat: String, lon: String, credentials: ConnectorCredentials) async throws -> String {
        let (data, _) = try await weatherGet(
            path: "/data/3.0/onecall",
            queryItems: [
                URLQueryItem(name: "lat", value: lat),
                URLQueryItem(name: "lon", value: lon),
                URLQueryItem(name: "exclude", value: "minutely,hourly"),
                URLQueryItem(name: "units", value: "metric"),
            ],
            credentials: credentials
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "(invalid response)"
        }
        return ConnectorsKit.formatWeatherAlerts(json)
    }

    private func weatherGet(path: String, queryItems: [URLQueryItem], credentials: ConnectorCredentials) async throws -> (Data, Int) {
        guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
            throw ConnectorProviderError.noCredentials
        }
        var components = URLComponents(string: "https://api.openweathermap.org" + path)!
        var allItems = queryItems
        allItems.append(URLQueryItem(name: "appid", value: apiKey))
        components.queryItems = (components.queryItems ?? []) + allItems
        guard let url = components.url else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid URL")
        }
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return (data, http.statusCode)
        case 401: throw ConnectorProviderError.authenticationFailed
        case 429:
            throw ConnectorProviderError.rateLimited(retryAfter: nil)
        default:
            throw ConnectorProviderError.apiError(statusCode: http.statusCode, message: "OpenWeatherMap API error")
        }
    }
}

// MARK: - RSS Provider

struct RSSProvider: ConnectorProvider {
    static let definitionId = "util.rss"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "fetch_feed":
            guard let url = params["url"] else { throw ConnectorProviderError.missingParameter("url") }
            let maxEntries = Int(params["maxEntries"] ?? "10") ?? 10
            data = try await fetchFeed(urlString: url, maxEntries: maxEntries)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        // RSS doesn't require auth; always return true
        true
    }

    // MARK: - Feed Parsing

    private func fetchFeed(urlString: String, maxEntries: Int) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid feed URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Failed to fetch feed")
        }
        let parser = RSSXMLParser(maxEntries: maxEntries)
        return parser.parse(data: data)
    }
}

// MARK: - RSS XML Parser

/// Simple RSS/Atom feed parser using Foundation XMLParser.
final class RSSXMLParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private let maxEntries: Int
    private var entries: [[String: String]] = []
    private var currentEntry: [String: String]?
    private var currentElement = ""
    private var currentText = ""
    private var isAtom = false
    private var isInItem = false

    init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    func parse(data: Data) -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return ConnectorsKit.formatRSSEntries(entries)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        currentText = ""

        if currentElement == "feed" {
            isAtom = true
        }

        if currentElement == "item" || (isAtom && currentElement == "entry") {
            isInItem = true
            currentEntry = [:]
        }

        // Atom link
        if isInItem && isAtom && currentElement == "link" {
            if let href = attributeDict["href"] {
                currentEntry?["link"] = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInItem && !trimmed.isEmpty {
            switch name {
            case "title": currentEntry?["title"] = trimmed
            case "link" where !isAtom: currentEntry?["link"] = trimmed
            case "description", "summary", "content":
                if currentEntry?["description"] == nil { currentEntry?["description"] = trimmed }
            case "pubdate", "published", "updated":
                if currentEntry?["pubDate"] == nil { currentEntry?["pubDate"] = trimmed }
            case "author", "dc:creator": currentEntry?["author"] = trimmed
            default: break
            }
        }

        if name == "item" || (isAtom && name == "entry") {
            isInItem = false
            if let entry = currentEntry, entries.count < maxEntries {
                entries.append(entry)
            }
            currentEntry = nil
        }

        currentText = ""
    }
}

// MARK: - Webhook Provider

struct WebhookProvider: ConnectorProvider {
    static let definitionId = "util.webhook"

    func execute(action: String, params: [String: String], credentials: ConnectorCredentials) async throws -> ConnectorActionResult {
        let data: String

        switch action {
        case "call":
            guard let url = params["url"] else { throw ConnectorProviderError.missingParameter("url") }
            let method = params["method"] ?? "GET"
            let body = params["body"]
            let headers = params["headers"]
            data = try await callWebhook(urlString: url, method: method, body: body, headersJSON: headers)

        default:
            throw ConnectorProviderError.unknownAction(action)
        }

        let (formatted, truncated) = ConnectorsKit.formatActionResult(data)
        return ConnectorActionResult(
            connectorId: Self.definitionId,
            actionId: action,
            data: ConnectorsKit.sanitizeConnectorData(formatted),
            truncated: truncated
        )
    }

    func testConnection(credentials: ConnectorCredentials) async throws -> Bool {
        // Webhook is generic; always return true
        true
    }

    // MARK: - Webhook Call

    private func callWebhook(urlString: String, method: String, body: String?, headersJSON: String?) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Invalid webhook URL")
        }

        // Only allow GET and POST methods
        let httpMethod = method.uppercased()
        guard httpMethod == "GET" || httpMethod == "POST" else {
            throw ConnectorProviderError.apiError(statusCode: 0, message: "Only GET and POST methods are supported")
        }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod

        // Parse custom headers from JSON string
        if let headersJSON, !headersJSON.isEmpty,
           let headersData = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: headersData) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set body for POST
        if httpMethod == "POST", let body, !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorProviderError.networkError(URLError(.badServerResponse))
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "(binary response, \(data.count) bytes)"
        return ConnectorsKit.formatWebhookResponse(statusCode: http.statusCode, body: responseBody)
    }
}
