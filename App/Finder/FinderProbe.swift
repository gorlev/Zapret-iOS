import Foundation

/// Opens one address for Find a Strategy, the way ZapretMac's SiteCheck.fetch
/// does. There is no proxy to point at on iPhone: while a trial's tunnel is
/// up, the app's own traffic goes through it, and while it is down, directly.
nonisolated enum FinderProbe {
    enum Outcome: Equatable, Sendable {
        case ok(status: Int, milliseconds: Int)
        case failed(String)

        var isOK: Bool { if case .ok = self { true } else { false } }
    }

    static func url(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    /// Several addresses separated by spaces, commas, or new lines. Repeats of a host are dropped.
    @MainActor static func urls(from text: String) -> [URL] {
        var seen = Set<String>()
        return Domains.pieces(text).compactMap(url(from:)).filter { seen.insert($0.host?.lowercased() ?? "").inserted }
    }

    /// `timeout` is how long to wait for an answer; the whole load gets 2 s more.
    /// `tls` pins the TLS version (S-102); nil lets the system choose.
    static func fetch(_ url: URL, timeout: TimeInterval = 8, tls: TLSVersion? = nil) async -> Outcome {
        let config = URLSessionConfiguration.ephemeral
        if let tls {
            // Like curl's --tlsv1.3, and --tlsv1.2 --tls-max 1.2.
            let version: tls_protocol_version_t = tls == .tls13 ? .TLSv13 : .TLSv12
            config.tlsMinimumSupportedProtocolVersion = version
            config.tlsMaximumSupportedProtocolVersion = version
        }
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 2
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let start = Date.now
        do {
            let (_, response) = try await session.data(for: request)
            let ms = Int(Date.now.timeIntervalSince(start) * 1000)
            return .ok(status: (response as? HTTPURLResponse)?.statusCode ?? 0, milliseconds: ms)
        } catch let error as URLError {
            return .failed(describe(error))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Opens every address at the same time; the answers keep the given order.
    @concurrent static func fetchAll(_ urls: [URL], timeout: TimeInterval, tls: TLSVersion? = nil) async -> [Outcome] {
        await withTaskGroup(of: (Int, Outcome).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask { (i, await fetch(url, timeout: timeout, tls: tls)) }
            }
            var out = [Outcome](repeating: .failed(""), count: urls.count)
            for await (i, outcome) in group { out[i] = outcome }
            return out
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: String(localized: "Timed out")
        case .networkConnectionLost: String(localized: "Connection reset")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            String(localized: "Secure connection failed")
        case .cannotFindHost, .dnsLookupFailed: String(localized: "Site not found")
        case .cannotConnectToHost: String(localized: "Could not connect")
        case .notConnectedToInternet: String(localized: "No internet")
        case .cancelled: String(localized: "Cancelled")
        default: error.localizedDescription
        }
    }
}
