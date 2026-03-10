import Foundation
import Logging

/// Manages files attached to projects.
/// Files are stored at `~/.mcclaw/projects/{projectId}/files/`.
/// ZIP archives are automatically extracted.
@MainActor
@Observable
final class ProjectFileStore {
    static let shared = ProjectFileStore()

    private let logger = Logger(label: "ai.mcclaw.project-files")
    private let fileManager = FileManager.default

    private init() {}

    // MARK: - Paths

    /// Base directory for a project's files.
    func filesDir(for projectId: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".mcclaw/projects/\(projectId)/files", isDirectory: true)
    }

    /// Ensure the files directory exists.
    func ensureDirectory(for projectId: String) {
        try? fileManager.createDirectory(
            at: filesDir(for: projectId),
            withIntermediateDirectories: true
        )
    }

    // MARK: - List Files

    /// List all files in a project (non-recursive, top level).
    func listFiles(for projectId: String) -> [ProjectFile] {
        ensureDirectory(for: projectId)
        let dir = filesDir(for: projectId)

        guard let urls = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? Date()

            return ProjectFile(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                fileSize: size,
                modifiedAt: modified
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Add File

    /// Import a file into the project. If it's a ZIP, extract it.
    @discardableResult
    func addFile(from sourceURL: URL, toProject projectId: String) -> Bool {
        ensureDirectory(for: projectId)
        let dir = filesDir(for: projectId)
        let destURL = dir.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            // Remove existing file with same name
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }

            try fileManager.copyItem(at: sourceURL, to: destURL)
            logger.info("File added to project \(projectId): \(sourceURL.lastPathComponent)")

            // Auto-extract ZIP files
            if sourceURL.pathExtension.lowercased() == "zip" {
                extractZip(at: destURL, in: dir, projectId: projectId)
            }

            return true
        } catch {
            logger.error("Failed to add file: \(error)")
            return false
        }
    }

    // MARK: - Extract ZIP

    /// Extract a ZIP archive and remove the original .zip file.
    private func extractZip(at zipURL: URL, in directory: URL, projectId: String) {
        let extractDir = directory.appendingPathComponent(
            zipURL.deletingPathExtension().lastPathComponent,
            isDirectory: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", extractDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Remove the .zip file after successful extraction
                try? fileManager.removeItem(at: zipURL)
                logger.info("ZIP extracted for project \(projectId): \(zipURL.lastPathComponent)")
            } else {
                logger.warning("ZIP extraction failed with status \(process.terminationStatus)")
            }
        } catch {
            logger.error("Failed to run unzip: \(error)")
        }
    }

    // MARK: - Remove File

    /// Remove a file or directory from a project.
    func removeFile(name: String, fromProject projectId: String) {
        let url = filesDir(for: projectId).appendingPathComponent(name)
        try? fileManager.removeItem(at: url)
        logger.info("File removed from project \(projectId): \(name)")
    }

    // MARK: - Read File Contents

    /// Read the text content of a file (for context injection into AI prompts).
    /// Returns nil for binary files or files larger than 100KB.
    func readTextContent(of file: ProjectFile) -> String? {
        guard !file.isDirectory else { return readDirectoryContents(at: file.path) }
        guard file.fileSize < 100_000 else { return nil }

        let url = URL(fileURLWithPath: file.path)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    /// Recursively read text files in a directory.
    private func readDirectoryContents(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var result = ""
        var totalSize: Int64 = 0
        let maxTotalSize: Int64 = 200_000 // 200KB total limit

        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            let size = Int64(values?.fileSize ?? 0)
            if size > 50_000 { continue } // Skip individual files > 50KB
            totalSize += size
            if totalSize > maxTotalSize { break }

            if let data = try? Data(contentsOf: fileURL),
               let text = String(data: data, encoding: .utf8) {
                let relativePath = fileURL.path.replacingOccurrences(of: path + "/", with: "")
                result += "--- \(relativePath) ---\n\(text)\n\n"
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Build Context

    /// Build a context string from all project files for AI prompt injection.
    func buildFilesContext(for projectId: String) -> String? {
        let files = listFiles(for: projectId)
        guard !files.isEmpty else { return nil }

        var context = "[Project Files]\n"
        for file in files {
            if let content = readTextContent(of: file) {
                if file.isDirectory {
                    context += "Directory: \(file.name)/\n\(content)\n"
                } else {
                    context += "File: \(file.name)\n\(content)\n\n"
                }
            } else {
                context += "File: \(file.name) (binary, \(file.formattedSize))\n"
            }
        }
        context += "[End Project Files]\n"

        return context
    }
}

// MARK: - ProjectFile Model

struct ProjectFile: Identifiable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int64
    let modifiedAt: Date

    var formattedSize: String {
        if isDirectory { return "Folder" }
        if fileSize < 1024 { return "\(fileSize) B" }
        if fileSize < 1024 * 1024 { return "\(fileSize / 1024) KB" }
        return String(format: "%.1f MB", Double(fileSize) / 1_048_576.0)
    }

    var iconName: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "c", "cpp", "h", "php":
            return "doc.text"
        case "json", "xml", "yaml", "yml", "toml":
            return "doc.badge.gearshape"
        case "md", "txt", "rtf":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc"
        }
    }
}
