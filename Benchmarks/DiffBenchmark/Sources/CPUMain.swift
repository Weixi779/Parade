// Created by weixi on 2026/09/17.
import Foundation

@main struct CPUMain {
    static func main() throws {
        let directory = CommandLine.arguments.dropFirst().first ?? "results"
        let verified = verifyCore()
        print("Verified \(verified) engine cases plus staged replay and LIS/LCS oracle")
        var records: [[String: Any]] = []
        var checksum = 0
        func run<ID>(_ fixture: BenchFixture<ID>, idKind: String) {
            var rng = BenchRNG(state: UInt64(fixture.old.count) ^ 0x42454e4348)
            var engines = BenchEngine.allCases
            // Explicit workload budget, not a timeout or a performance result.
            let expensive = ["shuffle", "reverse", "replace-all", "mixed"].contains(fixture.name)
            if fixture.old.count > 1000 && expensive || fixture.old.count > 10000 {
                engines.removeAll { $0 == .standard }
                records.append(["lane":"diff", "engine":BenchEngine.standard.rawValue, "id":idKind,
                                "scenario":fixture.name,"n":fixture.old.count,"status":"skipped-workload-budget"])
            }
            var samples: [BenchEngine: [Double]] = [:]
            var plans: [BenchEngine: BenchPlan] = [:]
            for engine in engines {
                let p = makePlan(engine, fixture.old, fixture.new)
                validate(p, fixture.old, fixture.new)
                plans[engine] = p
            }
            for iteration in 0..<35 {
                engines.shuffle(using: &rng)
                for engine in engines {
                    let start = nanos()
                    let plan = makePlan(engine, fixture.old, fixture.new)
                    let elapsed = Double(nanos() - start) / 1e6
                    checksum &+= consume(plan) // Consume outside the timed interval.
                    if iteration >= 5 { samples[engine, default: []].append(elapsed) }
                }
            }
            for engine in engines {
                let p = plans[engine]!, values = samples[engine]!
                records.append(["lane":"diff","engine":engine.rawValue,"id":idKind,
                    "scenario":fixture.name,"n":fixture.old.count,"targetN":fixture.new.count,"status":"ok",
                    "medianMs":percentile(values,0.5),"p95Ms":percentile(values,0.95),"samplesMs":values,
                    "deletes":p.deletes.count,"inserts":p.inserts.count,"moves":p.moves.count,"updates":p.updates.count])
            }
        }
        for n in [100, 1000, 10000, 100000] {
            for fixture in fixtures(n) {
                run(fixture, idKind: "Int")
                run(stringFixture(fixture), idKind: "section-prefixed-String")
            }
            print("Completed CPU size \(n)")
        }
        let output: [String: Any] = ["date":ISO8601DateFormatter().string(from: Date()),
            "os":ProcessInfo.processInfo.operatingSystemVersionString,"verifiedEngineCases":verified,
            "warmups":5,"runs":30,"checksum":checksum,"records":records]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys])
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("cpu.json"))
        print("Saved cpu.json checksum=\(checksum)")
    }
}
