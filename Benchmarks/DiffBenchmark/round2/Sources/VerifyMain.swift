// Created by weixi on 2026/09/17.
import Foundation

@main struct VerifyMain {
    static func main() throws {
        let directory = CommandLine.arguments.dropFirst().first ?? "results"
        var validated = 0
        func check(_ fixture: UIFixture) {
            for timing in [ContentTiming.before,.after] {
                let stages = sectionPlan(fixture.old,fixture.new,content:timing)
                validateSectionPlan(fixture.old,fixture.new,stages)
                validated += 1
            }
            let stages = StagedChangeset(source:fixture.old,target:fixture.new).map { SectionStage(name:"DifferenceKit",changes:$0) }
            validateSectionPlan(fixture.old,fixture.new,stages)
            validated += 1
        }
        var tinyStates: [[UISection]] = []
        func sequences(_ prefix: [Int], _ remaining: [Int]) {
            for cut in 0...prefix.count {
                for order in [[0,1],[1,0]] {
                    tinyStates.append([UISection(model:UIHeader(id:order[0]),elements:prefix.prefix(cut).map { UIItem(id:"tiny-\($0)") }),
                                       UISection(model:UIHeader(id:order[1]),elements:prefix.dropFirst(cut).map { UIItem(id:"tiny-\($0)") })])
                }
            }
            for i in remaining.indices { var rest=remaining; let id=rest.remove(at:i); sequences(prefix+[id],rest) }
        }
        sequences([],Array(0..<3))
        for old in tinyStates {
            for new in tinyStates { check(.init(name:"exhaustive",old:old,new:new,group:"oracle")) }
        }
        for fixture in randomizedSectionFixtures(2000) { check(fixture) }
        var matrices: [[String:Any]] = []
        for fixture in [2,20,1000].flatMap(matrixFixtures) {
            check(fixture)
            for (name,timing) in [("LIS-before",ContentTiming.before),("LIS-after",.after)] {
                let stages = sectionPlan(fixture.old,fixture.new,content:timing)
                let counts = operationCounts(stages)
                if fixture.name == "section-rotate-left" || fixture.name == "section-rotate-right" {
                    precondition(counts["sectionMoves"]==1 && counts["itemMoves"]==0)
                }
                if fixture.name == "section-delete-without-item-deletes" { precondition(counts["itemDeletes"]==0) }
                if fixture.name == "section-insert-without-item-inserts" { precondition(counts["itemInserts"]==0) }
                var row: [String:Any] = ["engine":name,"scenario":fixture.name,"n":fixture.count,"counts":counts]
                row["stages"] = stages.map { ["name":$0.name,"counts":operationCounts([$0])] as [String:Any] }
                matrices.append(row)
            }
            let stages = StagedChangeset(source:fixture.old,target:fixture.new).map { SectionStage(name:"DifferenceKit",changes:$0) }
            matrices.append(["engine":"DifferenceKit","scenario":fixture.name,"n":fixture.count,"counts":operationCounts(stages)])
        }
        var permutationRecords: [[String:Any]] = []
        for n in [64,1000,10000] {
            let old = (0..<n).map { BenchItem(id:$0) }
            for (name,order) in permutations(n) {
                let lowerBound = n - permutationLISLength(order)
                if n<=64 { precondition(lowerBound == n-lcsOracle(Array(0..<n),order)) }
                for engine in BenchEngine.allCases {
                    if n>1000 && engine == .standard { continue }
                    let new=order.map { BenchItem(id:$0) }
                    let plan=makePlan(engine,old,new)
                    validate(plan,old,new)
                    if engine == .lis || engine == .standard { precondition(plan.moves.count == lowerBound) }
                    permutationRecords.append(["engine":engine.rawValue,"scenario":name,"n":n,
                        "moves":plan.moves.count,"lowerBound":lowerBound,
                        "ratio":Double(plan.moves.count)/Double(max(1,lowerBound))])
                }
            }
        }
        let output: [String:Any] = ["validatedSectionPlans":validated,"exhaustiveStates":tinyStates.count,
            "exhaustiveTransitions":tinyStates.count*tinyStates.count,"randomTransitions":2000,
            "matrix":matrices,"permutations":permutationRecords,
            "note":"Independent staged replay. Permutation oracle: Fenwick LIS, cross-checked with DP at n=64. No general section+item optimality claim."]
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:directory).appendingPathComponent("verification.json"))
        print("Verified \(validated) section plans, \(permutationRecords.count) permutation comparisons")
    }
}
