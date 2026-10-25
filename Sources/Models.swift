import Foundation

struct JobOptions: Codable {
    var repair = true
    var metrics = true
    var author = true
    var likes = true
    var collects = true
    var comments = true
    var statusOnly: Bool { !repair && !metrics }
}

struct NoteInput: Equatable {
    let original: String
    var noteID: String
}

struct NoteResult: Identifiable, Codable {
    var id = UUID()
    var original: String
    var noteID = ""
    var status = "等待处理"
    var shareURL = ""
    var expandedURL = ""
    var shareText = ""
    var author = ""
    var likes = ""
    var collects = ""
    var comments = ""
    var detail = ""
    var processedAt = ""
    var successful: Bool { status == "可访问" || status == "完成" }
}

enum ToolkitError: LocalizedError {
    case message(String)
    case stopped
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .stopped: return "已停止，未处理条目保留。"
        }
    }
}

final class StopToken {
    private let lock = NSLock()
    private var flag = false
    var stopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
    func stop() { lock.lock(); flag = true; lock.unlock() }
    func check() throws { if stopped { throw ToolkitError.stopped } }
    func pause(_ seconds: TimeInterval) throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { try check(); Thread.sleep(forTimeInterval: min(0.1, end.timeIntervalSinceNow)) }
    }
}
