import Foundation

enum ProcessRunner {
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 20,
                    stop: StopToken? = nil) throws -> String {
        try stop?.check()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let result = ProcessOutput()
        let drained = DispatchSemaphore(value: 0)
        try process.run()
        DispatchQueue.global().async {
            result.data = output.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if stop?.stopped == true || Date() > deadline {
                process.terminate()
                let grace = Date().addingTimeInterval(0.8)
                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.03) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                if stop?.stopped == true { throw ToolkitError.stopped }
                throw ToolkitError.message("操作超时（\(Int(timeout))秒），请确认应用宝和小红书仍在运行。")
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        _ = drained.wait(timeout: .now() + 2)
        let text = String(data: result.data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ToolkitError.message("本地安卓操作失败：\(String(text.prefix(350)))")
        }
        return text
    }
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

private final class ProcessOutput: @unchecked Sendable { var data = Data() }

enum ADBLocation {
    static func find(custom: String = "") throws -> URL {
        let fm = FileManager.default
        if !custom.isEmpty {
            let path = NSString(string: custom).expandingTildeInPath
            guard fm.isExecutableFile(atPath: path) else { throw ToolkitError.message("选定的安卓连接工具不可执行。") }
            return URL(fileURLWithPath: path)
        }
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.tencent.yybmac/reshub")
        let candidates = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for bucket in candidates.sorted(by: { $0.path > $1.path }) {
            let online = bucket.appendingPathComponent("app/online")
            let builds = (try? fm.contentsOfDirectory(at: online, includingPropertiesForKeys: nil)) ?? []
            for build in builds.sorted(by: { $0.path > $1.path }) {
                let adb = build.appendingPathComponent("vms/tools/adb")
                if fm.isExecutableFile(atPath: adb.path) { return adb }
            }
        }
        for path in ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"] where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw ToolkitError.message("未找到应用宝自带的安卓连接工具。请先安装并打开应用宝，或在连接设置中选择 adb。")
    }
}
