import Foundation

/// Checks tpws strategy flags in Swift before they are saved.
///
/// ZapretMac checks a strategy with `tpws --dry-run`. That is impossible on
/// iOS: tpws is linked into the tunnel extension as a function and can run
/// only once per process, and the app cannot start it at all. So this repeats
/// the rules tpws's own option parser (Vendor/zapret/tpws/tpws.c,
/// parse_params) applies to the desync flags a strategy may hold, and refuses
/// the flags the app sets itself. A strategy that passes here is one tpws
/// starts with.
public enum StrategyCheck {
    /// One thing wrong with the flags, in words for the editor.
    public struct Issue: Equatable, Sendable, Identifiable {
        public let message: String
        public var id: String { message }
    }

    /// Everything wrong with these flags, in order. Empty means tpws accepts them.
    public static func issues(_ arguments: [String]) -> [Issue] {
        var out: [Issue] = []
        func add(_ message: String) {
            if !out.contains(where: { $0.message == message }) { out.append(Issue(message: message)) }
        }
        for profile in StrategyProfiles.split(arguments) {
            var state = ProfileState()
            var i = 0
            while i < profile.count {
                let arg = profile[i]
                i += 1
                guard arg.hasPrefix("--"), arg.count > 2 else {
                    add(String(localized: "“\(arg)” is not a tpws flag. Flags start with --.", bundle: .main))
                    continue
                }
                let parts = arg.dropFirst(2).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                var value = parts.count == 2 ? String(parts[1]) : nil
                let flag = "--\(name)"
                if appManaged.contains(name) {
                    add(String(localized: "\(flag) is set by the app. Remove it.", bundle: .main))
                    continue
                }
                if linuxOnly.contains(name) {
                    add(String(localized: "\(flag) only works on Linux. tpws on iPhone does not know it.", bundle: .main))
                    continue
                }
                guard let kind = options[name] else {
                    add(String(localized: "tpws does not know \(flag).", bundle: .main))
                    continue
                }
                switch kind {
                case .none:
                    if value != nil { add(String(localized: "\(flag) takes no value.", bundle: .main)) }
                case .required:
                    // getopt also takes the value from the next word: --split-pos 2.
                    if value == nil, i < profile.count { value = profile[i]; i += 1 }
                    if value == nil { add(String(localized: "\(flag) needs a value, like \(flag)=…", bundle: .main)); continue }
                case .optional:
                    break
                }
                if let problem = state.read(name, value: value) { add(problem) }
            }
            if state.oobDisorderConflict {
                add(String(localized: "An out-of-band byte and disorder together break connections on iPhone, and tpws refuses them. Turn on only one of them.", bundle: .main))
            }
        }
        return out
    }

    public static func isValid(_ arguments: [String]) -> Bool { issues(arguments).isEmpty }

    // MARK: - Rules

    private enum ArgumentKind { case none, required, optional }

    /// tpws's long options in the Apple build that a strategy may use.
    private static let options: [String: ArgumentKind] = [
        "maxconn": .required, "maxfiles": .required, "ipcache-lifetime": .required, "ipcache-hostname": .optional,
        "max-orphan-time": .required,
        "hostcase": .none, "hostspell": .required, "hostdot": .none, "hostnospace": .none, "hostpad": .required,
        "domcase": .none, "split-http-req": .required, "split-tls": .required, "split-pos": .required,
        "split-any-protocol": .optional, "disorder": .optional, "oob": .optional, "oob-data": .required,
        "methodspace": .none, "methodeol": .none, "hosttab": .none, "unixeol": .none,
        "tlsrec": .required, "tlsrec-pos": .required,
        "hostlist-domains": .required, "hostlist-exclude-domains": .required,
        "comment": .optional,
        "local-rcvbuf": .required, "local-sndbuf": .required, "remote-rcvbuf": .required, "remote-sndbuf": .required,
        "no-resolve": .none, "resolver-threads": .required, "skip-nodelay": .none,
        "tamper-start": .required, "tamper-cutoff": .required, "connect-bind-addr": .required,
        "skip": .none, "filter-l3": .required, "filter-tcp": .required, "filter-l7": .required,
        "ipset-ip": .required, "ipset-exclude-ip": .required,
        "local-tcp-user-timeout": .required, "remote-tcp-user-timeout": .required,
        "hostlist-auto-retrans-threshold": .optional,
    ]

    /// Flags the app or the tunnel sets, or that point at files the extension does not have.
    private static let appManaged: Set<String> = [
        "help", "h", "bind-addr", "bind-iface4", "bind-iface6", "bind-linklocal", "bind-wait-ifup",
        "bind-wait-ip", "bind-wait-ip-linklocal", "bind-wait-only", "port", "daemon", "user", "uid",
        "hostlist", "hostlist-exclude", "hostlist-auto", "hostlist-auto-fail-threshold",
        "hostlist-auto-fail-time", "hostlist-auto-debug", "pidfile", "debug", "debug-level", "dry-run",
        "version", "socks", "ipset", "ipset-exclude",
    ]

    private static let linuxOnly: Set<String> = ["mss", "fix-seg", "nosplice", "enable-pf"]

    private static let markers: Set<String> = ["host", "endhost", "sld", "midsld", "endsld", "method", "sniext"]
    private static let maxSplits = 16

    /// What one desync profile has set so far, for rules that span flags.
    private struct ProfileState {
        var splits = 0
        var oobScopes: Set<ProtocolScope> = []
        var disorderScopes: Set<ProtocolScope> = []

        /// tpws's check_oob_disorder: oob and disorder on the same traffic.
        var oobDisorderConflict: Bool {
            (oobScopes.contains(.all) && !disorderScopes.isEmpty)
                || (oobScopes.contains(.http) && (disorderScopes.contains(.all) || disorderScopes.contains(.http)))
                || (oobScopes.contains(.tls) && (disorderScopes.contains(.all) || disorderScopes.contains(.tls)))
        }

        /// The problem with one flag's value, or nil.
        mutating func read(_ name: String, value: String?) -> String? {
            let flag = "--\(name)"
            let v = value ?? ""
            switch name {
            case "split-pos":
                let items = v.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard items.allSatisfy(StrategyCheck.isSplitPosition) else {
                    return String(localized: "\(flag)=\(v) is not a list of positions. Use numbers (not 0) or markers like 1,midsld or sniext+1.", bundle: .main)
                }
                splits += items.count
                if splits > StrategyCheck.maxSplits {
                    return String(localized: "Too many split positions. tpws takes at most \(StrategyCheck.maxSplits).", bundle: .main)
                }
            case "split-http-req", "split-tls":
                splits += 1
                if splits > StrategyCheck.maxSplits {
                    return String(localized: "Too many split positions. tpws takes at most \(StrategyCheck.maxSplits).", bundle: .main)
                }
            case "tlsrec":
                guard StrategyCheck.isSplitPosition(v) || ["sni", "sniext", "snisld"].contains(v) else {
                    return String(localized: "\(flag)=\(v) is not a position. Use a number or a marker like sniext+1.", bundle: .main)
                }
            case "tlsrec-pos":
                guard let n = Int(v), n != 0, Int16(exactly: n) != nil else {
                    return String(localized: "\(flag) needs a number that is not 0.", bundle: .main)
                }
            case "hostspell":
                if v.count != 4 { return String(localized: "Host spelling must be exactly 4 letters, like hoSt.", bundle: .main) }
            case "hostpad", "maxconn", "maxfiles", "ipcache-lifetime", "max-orphan-time", "local-rcvbuf",
                 "local-sndbuf", "remote-rcvbuf", "remote-sndbuf", "local-tcp-user-timeout", "remote-tcp-user-timeout":
                if UInt(v) == nil { return String(localized: "\(flag) needs a whole number, like \(flag)=1024.", bundle: .main) }
            case "resolver-threads":
                guard let n = Int(v), (1...300).contains(n) else {
                    return String(localized: "\(flag) must be between 1 and 300.", bundle: .main)
                }
            case "oob-data":
                if !StrategyCheck.isOOBByte(v) {
                    return String(localized: "The out-of-band byte must be one character or 0x and two hex digits, like 0x01.", bundle: .main)
                }
            case "disorder", "oob":
                guard let scope = value.map(ProtocolScope.init(rawValue:)) ?? .all, value != "all" else {
                    return String(localized: "\(flag) takes no value, http, or tls.", bundle: .main)
                }
                if name == "disorder" { disorderScopes.insert(scope) } else { oobScopes.insert(scope) }
            case "filter-tcp":
                let items = v.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                if !items.allSatisfy(StrategyCheck.isPortFilter) {
                    return String(localized: "\(flag)=\(v) is not a port list. Use ports and ranges like 80,443 or 1000-2000.", bundle: .main)
                }
            case "filter-l7":
                let items = v.split(separator: ",", omittingEmptySubsequences: false)
                if !items.allSatisfy({ ["http", "tls", "unknown"].contains($0) }) {
                    return String(localized: "\(flag) takes http, tls, or unknown, separated by commas.", bundle: .main)
                }
            case "filter-l3":
                let items = v.split(separator: ",", omittingEmptySubsequences: false)
                if !items.allSatisfy({ $0 == "ipv4" || $0 == "ipv6" }) {
                    return String(localized: "\(flag) takes ipv4, ipv6, or both.", bundle: .main)
                }
            case "tamper-start", "tamper-cutoff":
                let digits = v.hasPrefix("n") ? String(v.dropFirst()) : v
                if UInt(digits) == nil {
                    return String(localized: "\(flag) needs a byte offset like 100, or n and a block number like n2.", bundle: .main)
                }
            default:
                break
            }
            return nil
        }
    }

    /// tpws's parse_split_pos: a non-zero number, or a marker with an optional +N or -N.
    static func isSplitPosition(_ s: String) -> Bool {
        if let n = Int(s.hasPrefix("+") ? String(s.dropFirst()) : s) { return n != 0 && Int16(exactly: n) != nil }
        guard let cut = s.firstIndex(where: { $0 == "+" || $0 == "-" }) else { return markers.contains(s) }
        let offset = s[cut...]
        guard markers.contains(String(s[..<cut])),
              let n = Int(offset.hasPrefix("+") ? String(offset.dropFirst()) : String(offset)) else { return false }
        return Int16(exactly: n) != nil
    }

    /// tpws's --oob-data: one character, or 0xHH.
    static func isOOBByte(_ s: String) -> Bool {
        if s.count == 1 { return true }
        return s.count == 4 && s.hasPrefix("0x") && UInt8(s.dropFirst(2), radix: 16) != nil
    }

    /// tpws's pf_parse: *, a port, or a range, optionally negated with ~.
    static func isPortFilter(_ s: String) -> Bool {
        if s == "*" { return true }
        let body = s.hasPrefix("~") ? String(s.dropFirst()) : s
        let ends = body.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(ends.count), ends.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) }) else { return false }
        let values = ends.compactMap { UInt16($0) }
        guard values.count == ends.count else { return false }
        return values.count == 1 || values[0] <= values[1]
    }
}
