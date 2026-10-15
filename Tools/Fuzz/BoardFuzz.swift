// A libFuzzer harness for the board loader (DESIGN.md §13, §15). It's compiled together with
// BoardKit's sources into one module, so it needs no package setup:
//
//     Tools/Fuzz/run.sh 60     # fuzz for 60 seconds (Linux, Swift 6)
//
// Whatever bytes come in, loading must fail cleanly or give a board that saves, and saving
// what was loaded and loading it again must change nothing.
import Foundation

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzBoardLoader(_ start: UnsafePointer<UInt8>?, _ count: Int) -> CInt {
    guard let start else { return 0 }
    let data = Data(bytes: start, count: count)
    guard let first = try? BoardCodec.decode(data) else { return 0 }

    let saved: Data
    do {
        saved = try BoardCodec.encode(first.board)
    } catch {
        fatalError("A loaded board couldn't be saved: \(error)")
    }
    guard let second = try? BoardCodec.decode(saved) else {
        fatalError("A saved board couldn't be loaded again")
    }
    precondition(
        second.report.skippedItems == 0 && second.report.adjustedValues == 0,
        "Loading a saved board had to repair it: \(second.report)"
    )
    precondition((try? BoardCodec.encode(second.board)) == saved, "Saving a reloaded board changed it")
    return 0
}
