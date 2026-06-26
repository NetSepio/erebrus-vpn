import Foundation

enum FilePath {
    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static var sharedDirectory: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TunnelConstants.appGroup
        ) else {
            fatalError("App Group \(TunnelConstants.appGroup) is not configured")
        }
        return url
    }

    static var workingDirectory: URL {
        sharedDirectory.appendingPathComponent("Working", isDirectory: true)
    }

    static var cacheDirectory: URL {
        sharedDirectory.appendingPathComponent("Cache", isDirectory: true)
    }
}