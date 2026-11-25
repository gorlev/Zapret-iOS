import Foundation

// Copied from ZapretMacKit's ScanPlan.swift.

/// How deep Find a Strategy looks: the built-in strategies, or zapret
/// blockcheck.sh's whole tpws matrix.
nonisolated enum ScanDepth: String, CaseIterable, Identifiable, Sendable {
    case quick, thorough
    var id: String { rawValue }
}

/// One try of a thorough scan: a set of tpws flags with a stable id and a
/// short name built from the flags.
nonisolated struct ScanTry: Identifiable, Equatable, Sendable {
    /// "scan:<flags>", stable across runs.
    let id: String
    let name: String
    let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
        self.id = ScanPlan.idPrefix + arguments.joined(separator: " ")
        self.name = ScanPlan.name(for: arguments)
    }

    /// The flags as one line, for showing under the name.
    var flags: String { arguments.joined(separator: " ") }
}

/// blockcheck.sh's tpws test matrix, with ZapretMac's rules: `--oob` and
/// `--disorder` are never combined, and `--mss` and `--fix-seg` (Linux only)
/// are never used.
nonisolated enum ScanPlan {
    static let idPrefix = "scan:"

    /// The tries for an address: the HTTP set for http://, the HTTPS set otherwise.
    static func tries(for url: URL) -> [ScanTry] {
        url.scheme?.lowercased() == "http" ? http : https
    }

    /// 13 split and TLS-record variants, each alone, with --oob, and with --disorder.
    static var https: [ScanTry] {
        let splits = ["2", "1", "sniext+1", "sniext+4", "host+1", "midsld", "1,midsld",
                      "1,sniext+1,host+1,midsld,endhost-1"].map { ["--split-pos=\($0)"] }
        let records: [[String]] = [
            ["--tlsrec=midsld"],
            ["--tlsrec=sniext+1", "--split-pos=midsld"],
            ["--tlsrec=sniext+4", "--split-pos=midsld"],
            ["--tlsrec=sniext+1", "--split-pos=1,midsld"],
            ["--tlsrec=sniext+4", "--split-pos=1,midsld"],
        ]
        return (splits + records).flatMap { base in
            [base, base + ["--oob"], base + ["--disorder"]].map(ScanTry.init)
        }
    }

    /// Header tricks, Host padding, three splits (alone, with --hostcase,
    /// --oob, --disorder), then the method tricks.
    static var http: [ScanTry] {
        var out: [[String]] = ["--hostcase", "--hostspell=hoSt", "--hostdot", "--hosttab", "--hostnospace", "--domcase"]
            .map { [$0] }
        out += [1024, 2048, 4096, 8192, 16384].map { ["--hostpad=\($0)"] }
        for pos in ["method+2", "midsld", "method+2,midsld"] {
            let base = ["--split-pos=\(pos)"]
            out += [base, base + ["--hostcase"], base + ["--oob"], base + ["--disorder"]]
        }
        out += [["--methodspace"], ["--unixeol"], ["--methodeol"]]
        return out.map(ScanTry.init)
    }

    /// A short human name: "TLS records at sniext+4 · Split at 1,midsld · Disorder".
    static func name(for arguments: [String]) -> String {
        let parts = arguments.map { arg -> String in
            let pieces = arg.split(separator: "=", maxSplits: 1).map(String.init)
            let value = pieces.count == 2 ? pieces[1] : ""
            switch pieces[0] {
            case "--tlsrec": return String(localized: "TLS records at \(value)")
            case "--split-pos": return String(localized: "Split at \(value)")
            case "--oob": return String(localized: "OOB")
            case "--disorder": return String(localized: "Disorder")
            case "--hostcase": return String(localized: "Host case")
            case "--hostspell": return String(localized: "Host spelled \(value)")
            case "--hostdot": return String(localized: "Dot after host")
            case "--hosttab": return String(localized: "Tab after host")
            case "--hostnospace": return String(localized: "No space after Host:")
            case "--domcase": return String(localized: "MiXeD domain case")
            case "--hostpad": return String(localized: "Host padding \(value)")
            case "--methodspace": return String(localized: "Extra space after method")
            case "--unixeol": return String(localized: "Unix line endings")
            case "--methodeol": return String(localized: "Line break before method")
            default: return arg
            }
        }
        return parts.joined(separator: " · ")
    }
}

extension Trial {
    /// A try from a thorough scan, not a built-in strategy.
    nonisolated var isScan: Bool { id.hasPrefix(ScanPlan.idPrefix) }
}
