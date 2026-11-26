import Darwin
import Foundation
import NetworkExtension

/// The bypass: every app's TCP traffic arrives here as IP packets on the
/// tunnel. hev-socks5-tunnel turns them back into connections and hands them to
/// tpws (SOCKS5 on 127.0.0.1), which reshapes the first packets and connects to
/// the real site. The extension's own sockets skip the tunnel, so nothing loops.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        nonisolated(unsafe) let provider = self
        Task {
            do {
                try await provider.start()
                done(nil)
            } catch {
                done(error)
            }
        }
    }

    private func start() async throws {
        TunnelLog.reset()
        var config: TunnelConfig
        do { config = try TunnelConfig.load() } catch {
            TunnelLog.write("Could not read the settings: \(error.localizedDescription)")
            throw TunnelError.noConfig
        }
        // Sharing: the Wi-Fi address other devices can reach, if there is one.
        config.shareAddress = nil
        if config.shareOnNetwork {
            config.shareAddress = NetworkShare.choose(from: NetworkShare.currentAddresses(), preferred: "en0")?.ip
            TunnelLog.write(config.shareAddress.map { "Sharing on \($0):\(TunnelConfig.socksPort)." }
                ?? "Sharing is on, but there is no Wi-Fi address.")
        }
        // tpws logs to a fresh file each start.
        try? Data().write(to: AppGroup.logURL)
        TunnelLog.write("Starting tpws: \(config.tpwsArguments.dropFirst().joined(separator: " "))")
        Engines.startTPWS(config.tpwsArguments)
        guard await Engines.waitForTPWS() else {
            TunnelLog.write("tpws did not start listening on port \(TunnelConfig.socksPort).")
            throw TunnelError.tpwsFailed
        }

        try await setTunnelNetworkSettings(Self.networkSettings(dns: config.dns))

        let fd = zapret_tun_fd()
        guard fd >= 0 else {
            TunnelLog.write("Could not find the tunnel's file descriptor.")
            throw TunnelError.noTunnel
        }
        Engines.startHev(tunFD: fd)
        TunnelLog.write("Tunnel up.")
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        TunnelLog.write("Stopping (reason \(reason.rawValue)).")
        hev_socks5_tunnel_quit()
        completionHandler()
        // tpws cannot be stopped from inside; leaving the process ends it, so
        // the next start gets a fresh tpws.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    /// The app asks for counters with a message; the reply is JSON.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        var txp = 0, txb = 0, rxp = 0, rxb = 0
        hev_socks5_tunnel_stats(&txp, &txb, &rxp, &rxb)
        let stats = ["txBytes": txb, "rxBytes": rxb, "txPackets": txp, "rxPackets": rxp]
        completionHandler?(try? JSONEncoder().encode(stats))
    }

    private static func networkSettings(dns: DNSChoice) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500
        let v4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        v4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = v4
        let v6 = NEIPv6Settings(addresses: ["fd66:7a70:7265::1"], networkPrefixLengths: [64])
        v6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = v6

        switch dns {
        case .cloudflare:
            let doh = NEDNSOverHTTPSSettings(servers: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"])
            doh.serverURL = URL(string: "https://cloudflare-dns.com/dns-query")
            doh.matchDomains = [""]
            settings.dnsSettings = doh
        case .google:
            let doh = NEDNSOverHTTPSSettings(servers: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888"])
            doh.serverURL = URL(string: "https://dns.google/dns-query")
            doh.matchDomains = [""]
            settings.dnsSettings = doh
        }
        return settings
    }
}

enum TunnelError: LocalizedError {
    case noConfig, tpwsFailed, noTunnel

    var errorDescription: String? {
        switch self {
        case .noConfig: String(localized: "The tunnel has no settings. Open Zapret and turn it on again.")
        case .tpwsFailed: String(localized: "tpws did not start. See the log.")
        case .noTunnel: String(localized: "The tunnel could not be opened.")
        }
    }
}

/// tpws and hev-socks5-tunnel each run their own blocking loop on a thread.
enum Engines {
    nonisolated(unsafe) private static var tpwsStarted = false

    static func startTPWS(_ arguments: [String]) {
        guard !tpwsStarted else { return }
        tpwsStarted = true
        let thread = Thread {
            // tpws keeps pointers into argv, so the strings are never freed.
            var argv = arguments.map { strdup($0) }
            argv.append(nil)
            let code = tpws_main(Int32(arguments.count), &argv)
            TunnelLog.write("tpws exited with code \(code).")
        }
        thread.stackSize = 1 << 20
        thread.name = "tpws"
        thread.start()
    }

    /// True once tpws accepts connections, within about three seconds.
    static func waitForTPWS() async -> Bool {
        for _ in 0..<30 {
            if canConnect(port: TunnelConfig.socksPort) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func startHev(tunFD: Int32) {
        let yaml = """
        tunnel:
          mtu: 1500
        socks5:
          port: \(TunnelConfig.socksPort)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 24576
          log-level: warn
        """
        let thread = Thread {
            let bytes = Array(yaml.utf8)
            let code = hev_socks5_tunnel_main_from_str(bytes, UInt32(bytes.count), tunFD)
            TunnelLog.write("hev-socks5-tunnel exited with code \(code).")
        }
        thread.stackSize = 1 << 20
        thread.name = "hev"
        thread.start()
    }

    private static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

/// A small log of what the extension did, which the app shows on the Log page.
enum TunnelLog {
    static func reset() { try? Data().write(to: AppGroup.tunnelLogURL) }

    static func write(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        guard let data = "[\(stamp)] \(line)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: AppGroup.tunnelLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: AppGroup.tunnelLogURL)
        }
    }
}
