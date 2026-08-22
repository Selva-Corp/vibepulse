// Local dedupe of answered request ids so the sheet vanishes at the tap
// instead of lingering until the server drops the entry (firmware twin:
// tk_needs_you_mark_answered, ring of 8).
import Foundation

struct AnsweredRing {
    private var ids: [String] = []
    private let capacity = 8

    mutating func mark(_ id: String) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) }
        ids.append(id)
        if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }
}
