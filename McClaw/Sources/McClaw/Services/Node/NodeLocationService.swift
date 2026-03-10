import Foundation
import CoreLocation
import Logging
import McClawKit

/// Location service using CLLocationManager.
@MainActor
final class NodeLocationService: NSObject {
    static let shared = NodeLocationService()

    private let logger = Logger(label: "ai.mcclaw.node.location")
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Get the current location.
    func getLocation(requestId: String) async -> BridgeInvokeResponse {
        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            return .failure(id: requestId, code: .permissionDenied, message: "Location access denied")
        }

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for authorization
            try? await Task.sleep(for: .milliseconds(500))

            let newStatus = locationManager.authorizationStatus
            if newStatus == .denied || newStatus == .restricted || newStatus == .notDetermined {
                return .failure(id: requestId, code: .permissionDenied, message: "Location permission not granted")
            }
        }

        do {
            let location = try await requestLocation()
            let result = LocationResult(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                timestamp: location.timestamp.timeIntervalSince1970
            )
            return .success(id: requestId, payload: result)
        } catch {
            return .failure(id: requestId, code: .internalError, message: error.localizedDescription)
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            locationManager.requestLocation()
        }
    }
}

extension NodeLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                continuation?.resume(returning: location)
                continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

struct LocationResult: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: TimeInterval
}
