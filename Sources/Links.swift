import Foundation

enum Links {
    static let shortHosts: Set<String> = ["xhslink.com", "www.xhslink.com", "xhslink.cn", "www.xhslink.cn"]
    static func official(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.user == nil && url.password == nil
            && (shortHosts.contains(host) || host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com"))
    }
    static func isShort(_ url: URL) -> Bool { official(url) && shortHosts.contains((url.host ?? "").lowercased()) }
    static func capture(_ text: String, _ pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
    static func noteID(_ url: URL) -> String? {
        guard official(url), !isShort(url) else { return nil }
        return capture(url.path, #"^/(?:explore|discovery/item)/(?:discovery\.)?([0-9a-f]{24})/?$"#)?.lowercased()
    }
    static func urls(_ text: String) -> [URL] {
        let clean = text.replacingOccurrences(of: "&amp;", with: "&")
        let pattern = #"https?://[^\s<>"'，。；、（）()\[\]{}]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap {
            guard let range = Range($0.range, in: clean) else { return nil }
            return URL(string: String(clean[range]).trimmingCharacters(in: CharacterSet(charactersIn: ";！!？?")))
        }
    }
    static func parse(_ text: String) -> [NoteInput] {
        var seen = Set<String>()
        return urls(text).compactMap { url in
            guard official(url) else { return nil }
            let id = noteID(url) ?? ""
            guard !id.isEmpty || (isShort(url) && url.path != "/" && !url.path.isEmpty) else { return nil }
            let key = id.isEmpty ? url.absoluteString : id
            guard seen.insert(key).inserted else { return nil }
            return NoteInput(original: url.absoluteString, noteID: id)
        }
    }
    static func deepLink(_ id: String) -> String { "xhsdiscover://item/\(id)" }
    static func isVideo(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "type" && $0.value == "video" } == true
    }
    static func resolve(_ url: URL, stop: StopToken) throws -> URL {
        try stop.check()
        guard official(url) else { throw ToolkitError.message("只接受小红书官方笔记链接。") }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "https"
        guard let secure = components.url else { throw ToolkitError.message("链接格式不正确。") }
        if noteID(secure) != nil { return secure }
        let delegate = RedirectGuard()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        var request = URLRequest(url: secure)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { _, response, error in
            box.url = response?.url; box.error = error; semaphore.signal()
        }
        task.resume()
        let deadline = Date().addingTimeInterval(22)
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if stop.stopped { task.cancel(); throw ToolkitError.stopped }
            if Date() > deadline { task.cancel(); throw ToolkitError.message("短链展开超时，不能据此判定笔记失效。") }
        }
        if let error = box.error { throw ToolkitError.message("短链展开失败：\(error.localizedDescription)") }
        guard !delegate.blocked, let landed = delegate.destination ?? box.url, noteID(landed) != nil else {
            throw ToolkitError.message("短链未跳转到可识别的笔记，保留原链接待核验。")
        }
        return landed
    }
}

private final class ResponseBox: @unchecked Sendable {
    var url: URL?
    var error: Error?
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var blocked = false
    var destination: URL?
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Links.official(url) else {
            blocked = true; completionHandler(nil); return
        }
        if Links.noteID(url) != nil {
            // Stop at the first note destination. Following it can land on a web risk/login page
            // and would discard the actual signed share target we already observed.
            var secure = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            secure.scheme = "https"
            destination = secure.url
            completionHandler(nil); return
        }
        guard url.scheme == "https" else { blocked = true; completionHandler(nil); return }
        completionHandler(request)
    }
}
