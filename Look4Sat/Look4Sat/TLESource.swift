//  Look4Sat iOS port — TLE network + local data layer
//  Ported from Kotlin: core/data/.../TleRepository.kt + CelesTrak/SatNOGS sources
//  License: GPL-3.0
//
//  Downloads TLE sets from the configured URLs and caches them locally.
//  SQLite is not used yet; TLE text is stored in the app's documents dir
//  which is simpler for a read-only TLE feed and matches the Android
//  app's actual behaviour (Room stores parsed SatItem rows, but the
//  source of truth is the downloaded TLE text).
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads and caches TLE data.
final class  TLESource {
    /// Default CelesTrak GP-2 / visual satellite feeds.
    static let defaultURLs: [String] = [
        "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=tle",
        "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=tle"
    ]

    private let cacheDir: URL
    private let session: URLSession

    public init(cacheDir: URL = URL.documentsDirectory, session: URLSession = .shared) {
        self.cacheDir = cacheDir
        self.session = session
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Fetch TLE text from all URLs, concatenate, and cache on disk.
    @discardableResult
    public func refresh(from urls: [String] = TLESource.defaultURLs) async throws -> String {
        var combined: [String] = []
        for url in urls {
            guard let u = URL(string: url) else { continue }
            let (data, response) = try await session.data(from: u)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { continue }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                combined.append(text)
            }
        }
        let all = combined.joined(separator: "\n")
        let path = cacheDir.appendingPathComponent("tle_cache.txt")
        try all.write(to: path, atomically: true, encoding: .utf8)
        return all
    }

    /// Load the cached TLE text, or fetch fresh if the cache is missing.
    public func loadCached() async -> String {
        let path = cacheDir.appendingPathComponent("tle_cache.txt")
        if let text = try? String(contentsOf: path, encoding: .utf8), !text.isEmpty {
            return text
        }
        // Fall through to a network refresh.
        return (try? await refresh()) ?? ""
    }
}

extension URL {
    static var documentsDirectory: URL {
        #if os(Windows)
        let home = ProcessInfo.processInfo.environment["USERPROFILE"]
            ?? ProcessInfo.processInfo.environment["HOME"] ?? "/"
        let url = URL(fileURLWithPath: home).appendingPathComponent(".look4sat")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }
}
