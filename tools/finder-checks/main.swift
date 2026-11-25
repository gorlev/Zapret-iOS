import Foundation

// Find a Strategy's pure logic, ported from ZapretMac's ScanPlanTests and
// BlockDiagnosisTests (and Trial's rules). Run with tools/check-finder.sh.

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL line \(line) \(message)")
    }
}

// MARK: ScanPlan

expect(ScanPlan.https.count == 39)
// 6 header tricks + 5 paddings + 3 splits x 4 + 3 method tricks
expect(ScanPlan.http.count == 26)
expect(ScanPlan.tries(for: URL(string: "http://example.com")!) == ScanPlan.http)
expect(ScanPlan.tries(for: URL(string: "https://example.com")!) == ScanPlan.https)
for t in ScanPlan.https + ScanPlan.http {
    expect(!(t.arguments.contains("--oob") && t.arguments.contains("--disorder")), t.flags)
    expect(!t.arguments.contains { $0.hasPrefix("--mss") || $0.hasPrefix("--fix-seg") }, t.flags)
}
for set in [ScanPlan.https, ScanPlan.http] { expect(Set(set.map(\.id)).count == set.count) }
let all = ScanPlan.https + ScanPlan.http
expect(all.allSatisfy { $0.id.hasPrefix(ScanPlan.idPrefix) })
expect(Trial(id: all[0].id, name: all[0].name, arguments: all[0].arguments).isScan)
expect(!Trial(id: "oob", name: "", arguments: []).isScan)
let httpsFlags = Set(ScanPlan.https.map(\.flags))
expect(httpsFlags.contains("--split-pos=1,sniext+1,host+1,midsld,endhost-1 --oob"))
expect(httpsFlags.contains("--tlsrec=sniext+4 --split-pos=1,midsld --disorder"))
expect(httpsFlags.contains("--tlsrec=midsld"))
let httpFlags = Set(ScanPlan.http.map(\.flags))
expect(httpFlags.contains("--hostspell=hoSt"))
expect(httpFlags.contains("--hostpad=16384"))
expect(httpFlags.contains("--split-pos=method+2,midsld --hostcase"))
expect(ScanPlan.http.last?.flags == "--methodeol")
expect(ScanTry(arguments: ["--split-pos=sniext+1", "--oob"]).name == "Split at sniext+1 · OOB")
expect(ScanTry(arguments: ["--tlsrec=sniext+4", "--split-pos=1,midsld", "--disorder"]).name
    == "TLS records at sniext+4 · Split at 1,midsld · Disorder")

// MARK: BlockDiagnosis (S-101)

expect(BlockDiagnosis.dnsVerdict(system: ["93.184.215.14", "2606:2800::1"],
                                 doh: [["93.184.215.14"], ["93.184.215.14", "93.184.215.15"], nil]) == .agrees)
let doh: [[String]?] = [["162.159.128.233", "162.159.130.233"], ["162.159.130.233"], ["162.159.128.233", "162.159.130.233"]]
expect(BlockDiagnosis.dnsVerdict(system: ["195.208.4.1"], doh: doh) == .spoofed)
expect(BlockDiagnosis.dnsVerdict(system: nil, doh: doh) == .spoofed)
expect(BlockDiagnosis.dnsVerdict(system: [], doh: doh) == .spoofed)
expect(BlockDiagnosis.dnsVerdict(system: ["127.0.0.1"], doh: [["1.2.3.4"], ["5.6.7.8"]]) == .spoofed)
expect(BlockDiagnosis.dnsVerdict(system: ["1.2.3.4"], doh: [nil, nil, []]) == .unknown)
expect(BlockDiagnosis.dnsVerdict(system: ["9.9.9.9"], doh: [["1.1.1.1"], ["2.2.2.2"]]) == .unknown)
expect(BlockDiagnosis.dnsVerdict(system: ["9.9.9.9"], doh: [["1.1.1.1"], nil]) == .unknown)
expect(BlockDiagnosis.dnsVerdict(system: ["2606:4700::1"], doh: [["1.1.1.1"], ["1.1.1.1"]]) == .unknown)

expect(BlockDiagnosis.kind(dns: .spoofed, opensDirectly: false, addressAnswers: nil, controlAnswers: nil) == .dns)
expect(BlockDiagnosis.kind(dns: .spoofed, opensDirectly: true, addressAnswers: nil, controlAnswers: nil) == .dns)
expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: true, addressAnswers: nil, controlAnswers: nil) == .none)
expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: false, addressAnswers: false, controlAnswers: true) == .ip)
expect(BlockDiagnosis.kind(dns: .agrees, opensDirectly: false, addressAnswers: false, controlAnswers: false) == .dpi)
expect(BlockDiagnosis.kind(dns: .unknown, opensDirectly: false, addressAnswers: true, controlAnswers: true) == .dpi)
expect(BlockKind.dns.message.contains("DNS over HTTPS"))
expect(BlockKind.ip.message.contains("cannot get around"))
expect(BlockKind.dpi.message.contains("A strategy can get around"))
expect(BlockKind.allCases.filter(\.strategyCanHelp) == [.dpi])

expect(BlockDiagnosis.isReserved("0.0.0.0"))
expect(BlockDiagnosis.isReserved("10.1.2.3"))
expect(BlockDiagnosis.isReserved("172.20.0.1"))
expect(!BlockDiagnosis.isReserved("172.32.0.1"))
expect(!BlockDiagnosis.isReserved("8.8.8.8"))
expect(!BlockDiagnosis.isIPv4("1.2.3"))
expect(!BlockDiagnosis.isIPv4("256.1.1.1"))

if let q = DNSMessage.query(host: "Example.com") {
    let expected: [UInt8] = [0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7] + Array("example".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1]
    expect([UInt8](q) == expected)
    expect(!DNSMessage.base64URL(q).contains("="))
    var answer = [UInt8](q)
    answer[2] = 0x81; answer[3] = 0x80; answer[7] = 2
    answer += [0xC0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, 2, 0xC0, 12]
    answer += [0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 215, 14]
    expect(DNSMessage.addresses(in: Data(answer)) == ["93.184.215.14"])
    var nx = [UInt8](q); nx[3] = 0x83
    expect(DNSMessage.addresses(in: Data(nx)) == [])
} else {
    expect(false, "query for Example.com")
}
expect(DNSMessage.addresses(in: Data([1, 2, 3])) == nil)
expect(DNSMessage.query(host: "") == nil)

// MARK: Trial (S-020, S-092, S-102)

func ok(_ site: String, _ ms: Int) -> SiteAttempt { SiteAttempt(site: site, result: .opens(milliseconds: ms)) }
func bad(_ site: String) -> SiteAttempt { SiteAttempt(site: site, result: .fails("Connection reset")) }

var two = Trial(id: "a", name: "A", arguments: [])
two.finish(with: [ok("a.com", 100), ok("b.com", 300)])
expect(two.status == .works(milliseconds: 300), "slowest site's time")
two.finish(with: [ok("a.com", 100), bad("b.com")])
expect(!two.works && two.isPartial && two.openCount == 1)
// A try works only if every repeat works.
expect(Trial.combine(repeats: [[ok("a.com", 100)], [bad("a.com")]]) == [bad("a.com")])
expect(Trial.combine(repeats: [[ok("a.com", 100)], [ok("a.com", 250)]]) == [ok("a.com", 250)])
var tls = Trial(id: "t", name: "T", arguments: [])
tls.finish(versions: [VersionResult(version: .tls13, sites: [ok("a.com", 200)]),
                      VersionResult(version: .tls12, sites: [bad("a.com")])])
expect(tls.works && tls.worksOnlyWithTLS13 && tls.works(with: .tls12) == false)
var both = Trial(id: "b", name: "B", arguments: [])
both.finish(versions: [VersionResult(version: .tls13, sites: [ok("a.com", 200)]),
                       VersionResult(version: .tls12, sites: [ok("a.com", 400)])])
expect(both.status == .works(milliseconds: 400) && !both.worksOnlyWithTLS13)
var fail = Trial(id: "f", name: "F", arguments: [])
fail.finish(with: [bad("a.com")])
let waiting = Trial(id: "w", name: "W", arguments: [])
let ranked = Trial.ranked([fail, waiting, tls, both]).map(\.id)
expect(ranked == ["b", "t", "w", "f"], "\(ranked)")

print(failures == 0 ? "All \(checks) finder checks passed." : "\(failures) of \(checks) finder checks failed.")
exit(failures == 0 ? 0 : 1)
