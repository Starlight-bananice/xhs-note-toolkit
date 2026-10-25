import AppKit
import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var options = JobOptions()
    @Published var results = [NoteResult]()
    @Published var selection = Set<UUID>()
    @Published var running = false
    @Published var status = "先在腾讯应用宝中打开并登录小红书，再粘贴笔记链接。"
    @Published var adbPath = UserDefaults.standard.string(forKey: "adbPath") ?? ""
    @Published var serial = UserDefaults.standard.string(forKey: "serial") ?? ""
    @Published var outputPath = UserDefaults.standard.string(forKey: "outputPath") ??
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/小红书笔记助手").path
    @Published var lastExport: URL?
    private var token: StopToken?
    var inputs: [NoteInput] { Links.parse(input) }
    var finished: Int { results.filter { !["等待处理", "处理中", "未完成"].contains($0.status) }.count }
    var retryable: Bool { results.contains { ["等待处理", "处理中", "未完成", "处理失败", "待核验", "部分完成", "访问受限", "需验证"].contains($0.status) } }

    init() {
        if let data = try? Data(contentsOf: Self.sessionURL), let saved = try? JSONDecoder().decode(SavedSession.self, from: data) {
            input = saved.input; options = saved.options
            results = saved.results.map { row in
                var r = row
                if r.status == "处理中" { r.status = "未完成" }
                return r
            }
            if !results.isEmpty { status = "已载入上次结果；可导出或继续未完成条目。" }
        }
    }
    func start(resume: Bool = false) {
        guard !running else { return }
        var selected = inputs
        var mapping = Array(selected.indices)
        if resume {
            mapping = results.indices.filter { !["完成", "可访问", "已删除", "重复笔记"].contains(results[$0].status) }
            selected = mapping.map { NoteInput(original: results[$0].original, noteID: results[$0].noteID) }
        } else { results = selected.map { NoteResult(original: $0.original, noteID: $0.noteID) } }
        guard !selected.isEmpty else { status = "没有可处理的官方短链或笔记长链。"; return }
        guard !options.metrics || options.author || options.likes || options.collects || options.comments else {
            status = "请至少选择一个要抓取的字段，或取消“抓取数据”。"; return
        }
        UserDefaults.standard.set(adbPath, forKey: "adbPath")
        UserDefaults.standard.set(serial, forKey: "serial")
        let token = StopToken(); self.token = token
        running = true
        let settings = options, path = adbPath, device = serial, text = input, directory = outputPath
        let indexes = mapping, batch = selected
        var snapshot = results
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var finalMessage = "本批处理完成。"
            do {
                try NoteRunner(stop: token).run(inputs: batch, options: settings, adbPath: path, serial: device,
                    progress: { index, row in
                        snapshot[indexes[index]] = row
                        Self.save(input: text, options: settings, results: snapshot)
                        DispatchQueue.main.async { self?.results[indexes[index]] = row }
                    }, message: { message in DispatchQueue.main.async { self?.status = message } })
            } catch { finalMessage = error.localizedDescription }
            Self.save(input: text, options: settings, results: snapshot)
            var exported: URL?
            if snapshot.contains(where: { $0.status != "等待处理" }) {
                do {
                    let url = try XLSXWriter.makeOutputURL(in: URL(fileURLWithPath: directory, isDirectory: true))
                    try XLSXWriter.write(rows: snapshot, to: url)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    exported = url
                } catch { finalMessage += " Excel 保存失败：\(error.localizedDescription)" }
            }
            let finalText = finalMessage, exportedFile = exported
            DispatchQueue.main.async {
                self?.running = false; self?.token = nil
                self?.status = finalText + (exportedFile == nil ? "" : " 已保存 Excel。")
                self?.lastExport = exportedFile
            }
        }
    }
    func stop() { token?.stop(); status = "正在停止，保留已取得的结果…" }
    func chooseOutput() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "保存到此文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path; UserDefaults.standard.set(outputPath, forKey: "outputPath")
        }
    }
    func chooseADB() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.prompt = "选择安卓连接工具"
        if panel.runModal() == .OK, let url = panel.url { adbPath = url.path }
    }
    func checkConnection() {
        guard !running else { return }
        running = true; status = "正在检查应用宝连接…"
        let path = adbPath, preferred = serial
        DispatchQueue.global().async { [weak self] in
            let message: String
            do {
                let stop = StopToken(), adb = try ADBLocation.find(custom: path)
                let serial = try AndroidSession.select(adb: adb, preferred: preferred, stop: stop)
                let result = try ProcessRunner.run(adb, ["-s", serial, "shell", "pm", "path", "com.xingin.xhs"])
                message = result.contains("package:") ? "已连接应用宝，安卓小红书可用（\(serial)）。" : "已连接安卓设备，但未找到小红书。"
            } catch { message = error.localizedDescription }
            DispatchQueue.main.async { self?.status = message; self?.running = false }
        }
    }
    func export() {
        do {
            let url = try XLSXWriter.makeOutputURL(in: URL(fileURLWithPath: outputPath, isDirectory: true))
            try XLSXWriter.write(rows: results, to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastExport = url; status = "已保存 Excel：\(url.lastPathComponent)"
        } catch { status = "Excel 保存失败：\(error.localizedDescription)" }
    }
    private static var sessionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/XHSNoteToolkit/session.json")
    }
    private static func save(input: String, options: JobOptions, results: [NoteResult]) {
        let url = sessionURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(SavedSession(input: input, options: options, results: results))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // The GUI reports the independent Excel save result at the end; avoid logging share credentials.
            NSLog("本地会话暂存失败：%@", error.localizedDescription)
        }
    }
}

private struct SavedSession: Codable { var input: String; var options: JobOptions; var results: [NoteResult] }
