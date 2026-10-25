import AppKit
import Foundation

final class AndroidSession {
    let adb: URL
    let serial: String
    let stop: StopToken
    private var bridge: Process?
    private let input = Pipe()
    private let output = Pipe()
    private let lines = LineQueue()
    private var remotePath = ""
    var display = 0

    init(adb: URL, serial: String, stop: StopToken) {
        self.adb = adb; self.serial = serial; self.stop = stop
    }
    static func devices(adb: URL, stop: StopToken) throws -> [String] {
        let text = try ProcessRunner.run(adb, ["devices", "-l"], stop: stop)
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count > 1 && parts[1] == "device" ? String(parts[0]) : nil
        }
    }
    static func select(adb: URL, preferred: String, stop: StopToken) throws -> String {
        let all = try devices(adb: adb, stop: stop)
        if !preferred.isEmpty {
            guard all.contains(preferred) else { throw ToolkitError.message("选定的安卓设备未连接，请先打开应用宝的小红书。") }
            return preferred
        }
        var candidates = [String]()
        for serial in all {
            let model = try ProcessRunner.run(adb, ["-s", serial, "shell", "getprop", "ro.product.device"], stop: stop)
            if model.trimmingCharacters(in: .whitespacesAndNewlines) == "haotian" { candidates.append(serial) }
        }
        guard candidates.count == 1 else {
            throw ToolkitError.message(candidates.isEmpty ? "没有找到正在运行的应用宝安卓设备。请先打开应用宝中的小红书。" : "发现多个应用宝设备，请在连接设置中指定设备编号。")
        }
        return candidates[0]
    }
    func command(_ args: [String], timeout: TimeInterval = 20) throws -> String {
        try ProcessRunner.run(adb, ["-s", serial] + args, timeout: timeout, stop: stop)
    }
    func shell(_ args: [String], timeout: TimeInterval = 20) throws -> String {
        try command(["shell", args.map(ProcessRunner.quote).joined(separator: " ")], timeout: timeout)
    }
    func start() throws {
        let package = try shell(["pm", "path", "com.xingin.xhs"])
        guard package.contains("package:") else { throw ToolkitError.message("当前安卓设备没有安装小红书。") }
        let windows = try shell(["dumpsys", "window", "windows"])
        display = Self.displayID(windows) ?? 0
        let resource = Bundle.main.resourceURL?.appendingPathComponent("toolkit-bridge.dex")
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/toolkit-bridge.dex")
        guard let dex = [resource, local].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ToolkitError.message("软件缺少安卓控件组件，请重新下载完整安装包。")
        }
        remotePath = "/data/local/tmp/xhs-note-toolkit-\(UUID().uuidString).dex"
        _ = try command(["push", dex.path, remotePath])
        _ = try shell(["chmod", "444", remotePath])
        let p = Process()
        p.executableURL = adb
        p.arguments = ["-s", serial, "shell", "-T", "CLASSPATH=\(ProcessRunner.quote(remotePath)) app_process / ToolkitBridge --server"]
        p.standardInput = input; p.standardOutput = output; p.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { self?.lines.close() } else { self?.lines.append(data) }
        }
        bridge = p
        try p.run()
        _ = try lines.next(prefix: "READY", timeout: 15, stop: stop)
    }
    static func displayID(_ windows: String) -> Int? {
        let blocks = windows.components(separatedBy: "Window #")
        for block in blocks where block.contains("com.xingin.xhs/") {
            if let id = Links.capture(block, #"mDisplayId=(\d+)"#), let value = Int(id) { return value }
        }
        return nil
    }
    func page() throws -> Page {
        var lastError: Error = ToolkitError.message("暂时未取得小红书窗口。")
        for _ in 0..<3 {
            try stop.check()
            try input.fileHandleForWriting.write(contentsOf: Data("dump\n".utf8))
            let text = try lines.next(prefix: "<?xml", timeout: 10, stop: stop)
            do { return try Page.read(text) }
            catch { lastError = error; try stop.pause(0.15) }
        }
        throw lastError
    }
    func open(noteID: String, video: Bool = false) throws {
        let route = video ? "xhsdiscover://video_feed/\(noteID)" : Links.deepLink(noteID)
        let report = try shell(["am", "start", "-W", "--display", String(display), "-a", "android.intent.action.VIEW", "-d", route, "-p", "com.xingin.xhs"])
        guard report.contains("Status: ok"), report.contains("NoteDetailActivity") || report.contains("DetailFeedActivity") else {
            throw ToolkitError.message("安卓客户端未确认打开笔记详情页，已停止本条处理。")
        }
    }
    func tap(_ node: UINode) throws {
        try stop.check()
        guard node.package == "com.xingin.xhs", node.display == display, !node.bounds.isEmpty else {
            throw ToolkitError.message("目标控件不属于当前小红书窗口，已停止点击。")
        }
        _ = try shell(["input", "-d", String(display), "tap", String(Int(node.bounds.midX)), String(Int(node.bounds.midY))])
    }
    func copyDirectly() throws -> Bool {
        try stop.check()
        try input.fileHandleForWriting.write(contentsOf: Data("copy\n".utf8))
        return try lines.next(prefix: "COPY_RESULT ", timeout: 5, stop: stop).trimmingCharacters(in: .whitespacesAndNewlines) == "COPY_RESULT true"
    }
    func back() throws { _ = try shell(["input", "-d", String(display), "keyevent", "KEYCODE_BACK"]) }
    func swipe(_ bounds: CGRect) throws {
        guard bounds.width > 100 && bounds.height > 30 else { throw ToolkitError.message("分享菜单横向区域无效。") }
        _ = try shell(["input", "-d", String(display), "swipe", String(Int(bounds.minX+bounds.width*0.85)),
                       String(Int(bounds.midY)), String(Int(bounds.minX+bounds.width*0.18)), String(Int(bounds.midY)), "420"])
    }
    func restore() throws {
        // Closing the target page before the next item prevents a stale note or delayed redirect from being read.
        for _ in 0..<5 {
            let p = try page()
            if p.isHome { return }
            try back()
            try stop.pause(0.25)
        }
        throw ToolkitError.message("没有恢复到小红书首页。为防止读取错笔记，已停止批次；请返回首页后重试。")
    }
    func close() {
        try? input.fileHandleForWriting.write(contentsOf: Data("quit\n".utf8))
        try? input.fileHandleForWriting.close()
        if let p = bridge, p.isRunning {
            let end = Date().addingTimeInterval(1)
            while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
            if p.isRunning { p.terminate() }
        }
        output.fileHandleForReading.readabilityHandler = nil
        if !remotePath.isEmpty {
            _ = try? ProcessRunner.run(adb, ["-s", serial, "shell", "rm", "-f", remotePath], timeout: 5)
        }
        bridge = nil; remotePath = ""
    }
    deinit { close() }
}

private final class LineQueue {
    private let condition = NSCondition()
    private var pending = Data()
    private var lines = [String]()
    private var ended = false
    func append(_ data: Data) {
        condition.lock(); defer { condition.unlock() }
        pending.append(data)
        while let i = pending.firstIndex(of: 10) {
            lines.append(String(data: pending[..<i], encoding: .utf8) ?? "")
            pending.removeSubrange(...i)
        }
        condition.broadcast()
    }
    func close() { condition.lock(); ended = true; condition.broadcast(); condition.unlock() }
    func next(prefix: String, timeout: TimeInterval, stop: StopToken) throws -> String {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try stop.check()
            while !lines.isEmpty {
                let line = lines.removeFirst()
                if let range = line.range(of: prefix) { return String(line[range.lowerBound...]) }
            }
            if ended { throw ToolkitError.message("安卓读取连接已断开，请确认应用宝仍在运行后重试。") }
            _ = condition.wait(until: min(deadline, Date().addingTimeInterval(0.1)))
        }
        throw ToolkitError.message("安卓界面读取超时，请确认小红书窗口已经打开。")
    }
}
