import AppKit
import Foundation

final class NoteRunner {
    let stop: StopToken
    init(stop: StopToken) { self.stop = stop }
    func run(inputs: [NoteInput], options: JobOptions, adbPath: String, serial: String,
             completedNoteIDs: Set<String> = [],
             progress: (Int, NoteResult) -> Void, message: (String) -> Void) throws {
        message("正在连接应用宝中的安卓小红书…")
        let adb = try ADBLocation.find(custom: adbPath)
        let device = try AndroidSession.select(adb: adb, preferred: serial, stop: stop)
        let session = AndroidSession(adb: adb, serial: device, stop: stop)
        defer { session.close() }
        try session.start()
        try session.restore()
        var seen = completedNoteIDs
        for (index, input) in inputs.enumerated() {
            try stop.check()
            var row = NoteResult(original: input.original, noteID: input.noteID)
            var recorded = false
            row.status = "处理中"
            progress(index, row)
            do {
                var destination = URL(string: input.original)!
                if row.noteID.isEmpty {
                    message("第 \(index+1)/\(inputs.count) 条：正在展开短链…")
                    let expanded = try Links.resolve(URL(string: input.original)!, stop: stop)
                    destination = expanded
                    row.noteID = Links.noteID(expanded) ?? ""
                }
                if !seen.insert(row.noteID).inserted {
                    row.status = "重复笔记"; row.detail = "与本批前面的链接指向同一篇笔记，已跳过。"
                    recorded = true; progress(index, row); continue
                }
                message("第 \(index+1)/\(inputs.count) 条：正在打开笔记…")
                try session.open(noteID: row.noteID, video: Links.isVideo(destination))
                let page = try waitForNote(session, statusOnly: options.statusOnly)
                if let hint = page.deletedHint {
                    row.status = "已删除"; row.detail = hint
                    row.processedAt = ISO8601DateFormatter().string(from: Date())
                    recorded = true
                    progress(index, row)
                    message("第 \(index+1)/\(inputs.count) 条：已记录失效结果。")
                    try NotePacing.afterDeletedNote(waitForAuthor: session.waitForAuthorProfile,
                                                   returnHome: session.restore, pause: stop.pause)
                    continue
                }
                if let hint = page.restriction {
                    row.status = hint.contains("验证") ? "需验证" : "访问受限"; row.detail = hint
                    progress(index, row)
                    throw ToolkitError.message("安卓客户端需要人工处理：\(hint)。已停止批次。")
                }
                row.status = "可访问"
                if options.metrics {
                    row.author = options.author ? page.author : ""
                    let metrics = page.metrics
                    row.likes = options.likes ? metrics.likes : ""
                    row.collects = options.collects ? metrics.collects : ""
                    row.comments = options.comments ? metrics.comments : ""
                }
                if options.repair {
                    message("第 \(index+1)/\(inputs.count) 条：正在从安卓分享面板复制链接…")
                    let shared = try share(session, page: page)
                    row.shareText = shared
                    guard let url = Links.urls(shared).first(where: Links.official) else {
                        throw ToolkitError.message("安卓复制的内容中没有小红书官方链接。")
                    }
                    row.shareURL = url.absoluteString // preserve exactly what Android copied, including every parameter
                    do {
                        let expanded = try Links.resolve(url, stop: stop)
                        guard Links.noteID(expanded) == row.noteID else {
                            row.shareURL = ""; row.shareText = ""
                            throw ToolkitError.message("客户端复制出的链接不属于目标笔记，已丢弃。")
                        }
                        row.expandedURL = expanded.absoluteString
                        row.status = "完成"
                    } catch ToolkitError.stopped { throw ToolkitError.stopped }
                    catch {
                        if row.shareURL.isEmpty { throw error }
                        row.status = "待核验"; row.detail = "已取得安卓分享原链，但未能展开核对笔记：\(error.localizedDescription)"
                    }
                }
                let missing = [(options.author, row.author), (options.likes, row.likes),
                               (options.collects, row.collects), (options.comments, row.comments)].contains { $0.0 && $0.1.isEmpty }
                if options.metrics && missing {
                    row.detail += (row.detail.isEmpty ? "" : "；") + "部分字段未读取到，空白表示未知，不作为 0。"
                    if row.status != "待核验" { row.status = "部分完成" }
                }
                row.processedAt = ISO8601DateFormatter().string(from: Date())
                recorded = true
                progress(index, row)
                if options.repair { try session.ensureNoteVisible() }
                message("第 \(index+1)/\(inputs.count) 条：已取得结果。")
                try NotePacing.afterReadableNote(pause: stop.pause, returnHome: session.restore)
            } catch ToolkitError.stopped {
                if !recorded {
                    row.status = "未完成"; row.detail = "本条已暂停，可继续处理。"
                    progress(index, row)
                }
                throw ToolkitError.stopped
            } catch {
                // A result is already checkpointed. Navigation or pause failures must not erase it
                // or trigger a second recovery that would interrupt the client's automatic redirect.
                if recorded { throw error }
                if row.status == "访问受限" || row.status == "需验证" { throw error }
                row.status = "处理失败"; row.detail = error.localizedDescription
                row.processedAt = ISO8601DateFormatter().string(from: Date())
                progress(index, row)
                // A recovery failure stops the whole batch instead of risking stale-page data.
                try session.restore()
                try stop.pause(2)
            }
        }
    }
    private func waitForNote(_ session: AndroidSession, statusOnly: Bool) throws -> Page {
        let deadline = Date().addingTimeInterval(statusOnly ? 8 : 18)
        var last: Page?
        while Date() < deadline {
            try stop.check()
            let page = try session.page(); last = page
            if page.deletedHint != nil || page.restriction != nil { return page }
            if statusOnly ? page.isReadableNote : page.isNote {
                // Status-only confirms the page structure; metric jobs also wait for counters.
                try stop.pause(statusOnly ? 0.15 : 0.35)
                let stable = try session.page()
                if stable.deletedHint != nil || stable.restriction != nil { return stable }
                if statusOnly ? stable.isReadableNote : stable.isNote { return stable }
            }
            try stop.pause(0.2)
        }
        let hint = last?.isHome == true ? "客户端跳回首页，未取得目标笔记。" : "未能确认目标笔记已加载。"
        throw ToolkitError.message(hint + "没有明确失效提示，不能判断为已删除。")
    }
    private func share(_ session: AndroidSession, page: Page) throws -> String {
        guard let button = page.shareButton else { throw ToolkitError.message("没有识别到安卓笔记的分享按钮。") }
        try session.tap(button)
        let deadline = Date().addingTimeInterval(8)
        var swipes = 0
        var directTried = false
        while Date() < deadline {
            let panel = try session.page()
            if let deleted = panel.deletedHint { throw ToolkitError.message(deleted) }
            if !directTried && (panel.labels.contains("分享至") || panel.labels.contains("分享到")) {
                directTried = true
                let before = NSPasteboard.general.changeCount
                if try session.copyDirectly() { return try waitForCopy(after: before) }
            }
            if let index = panel.find(exact: ["复制链接", "复制链接(推荐)", "Copy link"]), let copy = panel.clickable(index) {
                let pasteboard = NSPasteboard.general
                let before = pasteboard.changeCount
                try session.tap(copy)
                return try waitForCopy(after: before)
            }
            if swipes < 4, let strip = panel.shareStrip {
                try session.swipe(strip)
                swipes += 1
            }
            try stop.pause(0.2)
        }
        throw ToolkitError.message("安卓分享面板没有出现“复制链接”，未点击其他分享目标。")
    }
    private func waitForCopy(after before: Int) throws -> String {
        let copyDeadline = Date().addingTimeInterval(8)
        while Date() < copyDeadline {
            try stop.check()
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != before, let value = pasteboard.string(forType: .string),
               !Links.urls(value).filter(Links.official).isEmpty { return value }
            try stop.pause(0.15)
        }
        throw ToolkitError.message("安卓已点击复制链接，但 Mac 剪贴板没有同步新链接。请在应用宝内检查剪贴板同步。")
    }
}
