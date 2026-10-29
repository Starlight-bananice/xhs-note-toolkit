import AppKit
import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var options = JobOptions()
    @Published var results = [NoteResult]()
    @Published var selection = Set<UUID>()
    @Published var running = false
    @Published var status = "先在腾讯应用宝中打开小红书，再粘贴笔记链接；仅查有效性可使用未登录状态。"
    @Published var adbPath = UserDefaults.standard.string(forKey: "adbPath") ?? ""
    @Published var serial = UserDefaults.standard.string(forKey: "serial") ?? ""
    @Published var outputPath = UserDefaults.standard.string(forKey: "outputPath") ??
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/小红书笔记助手").path
    @Published var lastExport: URL?
    @Published var page = WorkspacePage.workbench
    @Published var history = [BatchRecord]()
    let updates = UpdateController()
    private let storage: BatchHistory
    private var currentBatch: BatchRecord?
    private var token: StopToken?
    var inputs: [NoteInput] { Links.parse(input) }
    var finished: Int { results.filter { !["等待处理", "处理中", "未完成"].contains($0.status) }.count }
    var retryable: Bool { results.contains(where: \.needsResume) }

    init(storage: BatchHistory = BatchHistory(), restoreUpdate: Bool = true) {
        self.storage = storage
        do {
            if let saved = try storage.current() {
                apply(saved)
                // Import the previous version's single saved session into history once.
                try storage.save(saved)
            }
            if restoreUpdate, let snapshot = try UpdateSession.take() {
                input = snapshot.input; options = snapshot.options; results = snapshot.results
                lastExport = snapshot.excelPath.map { URL(fileURLWithPath: $0) }
                status = snapshot.status
            }
            if restoreUpdate, let reason = try? String(contentsOf: UpdateSession.failureFile, encoding: .utf8) {
                status = reason
                try? FileManager.default.removeItem(at: UpdateSession.failureFile)
            }
            history = try storage.records()
        } catch { status = "读取本地记录失败：\(error.localizedDescription)" }
    }

    private func apply(_ record: BatchRecord) {
        let record = record.recovered()
        currentBatch = record; input = record.input; options = record.options; results = record.results
        selection.removeAll(); lastExport = record.excelPath.map { URL(fileURLWithPath: $0) }
        status = record.remaining > 0
            ? "已恢复记录，尚有 \(record.remaining) 条可续跑；点击“继续未完成”保留已有结果。"
            : "已载入历史结果，可查看或导出。"
    }
    func load(_ record: BatchRecord, resume: Bool = false) {
        guard !running, !updates.installing else { return }
        apply(record); page = .workbench
        do { try storage.save(record.recovered()) }
        catch { status = "记录暂存失败：\(error.localizedDescription)"; return }
        if resume { start(resume: true) }
    }

    func start(resume: Bool = false) {
        guard !running, !updates.installing else { return }
        var record: BatchRecord
        if resume {
            guard var saved = currentBatch else { status = "没有可续跑的历史任务。"; return }
            saved.results = results
            record = saved
        } else {
            let parsed = inputs
            guard !parsed.isEmpty else { status = "没有可处理的官方短链或笔记长链。"; return }
            record = BatchRecord(input: input, options: options,
                                 results: parsed.map { NoteResult(original: $0.original, noteID: $0.noteID) })
        }
        guard !record.options.metrics || record.options.author || record.options.likes || record.options.collects || record.options.comments else {
            status = "请至少选择一个要抓取的字段，或取消“抓取数据”。"; return
        }
        let indexes = resume ? record.resumeIndices : Array(record.results.indices)
        guard !indexes.isEmpty else { status = "这批笔记已处理完成，无需续跑。"; return }
        let batch = indexes.map { NoteInput(original: record.results[$0].original, noteID: record.results[$0].noteID) }
        let completedIDs = Set(record.results.filter { !$0.needsResume }.map(\.noteID).filter { !$0.isEmpty })
        record.state = "处理中"; record.updatedAt = Date()
        // Persist the entire queue before connecting, including items not reached yet.
        do { try storage.save(record) }
        catch { status = "无法保存断点，未开始处理：\(error.localizedDescription)"; return }
        apply(record); currentBatch = record; page = .workbench
        upsert(record)
        UserDefaults.standard.set(adbPath, forKey: "adbPath")
        UserDefaults.standard.set(serial, forKey: "serial")
        let token = StopToken(); self.token = token
        running = true; status = resume ? "正在继续未完成条目…" : "正在开始处理…"
        let path = adbPath, device = serial, directory = outputPath, storage = storage
        var checkpoint = record
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var finalMessage = "本批处理完成。"
            var persistenceError: String?
            var interrupted = false
            do {
                try NoteRunner(stop: token).run(inputs: batch, options: checkpoint.options, adbPath: path, serial: device,
                    completedNoteIDs: completedIDs,
                    progress: { index, row in
                        checkpoint.results[indexes[index]] = row; checkpoint.updatedAt = Date()
                        do { try storage.save(checkpoint) }
                        catch { persistenceError = error.localizedDescription; token.stop() }
                        let saved = checkpoint
                        DispatchQueue.main.async {
                            self?.results = saved.results; self?.currentBatch = saved; self?.upsert(saved)
                        }
                    }, message: { message in DispatchQueue.main.async { self?.status = message } })
            } catch { finalMessage = error.localizedDescription; interrupted = true }
            checkpoint.state = checkpoint.remaining == 0 ? "已完成" : (interrupted ? "已中断" : "待续跑")
            var exported: URL?
            if checkpoint.results.contains(where: { $0.status != "等待处理" }) {
                do {
                    let url = try XLSXWriter.makeOutputURL(in: URL(fileURLWithPath: directory, isDirectory: true))
                    try XLSXWriter.write(rows: checkpoint.results, to: url)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    exported = url; checkpoint.excelPath = url.path
                } catch { finalMessage += " Excel 保存失败：\(error.localizedDescription)" }
            }
            checkpoint.updatedAt = Date()
            do { try storage.save(checkpoint) }
            catch { persistenceError = error.localizedDescription }
            if let failure = persistenceError { finalMessage += " 断点保存失败：\(failure)" }
            if checkpoint.remaining > 0 { finalMessage += " 尚有 \(checkpoint.remaining) 条可点击“继续未完成”续跑。" }
            let finalText = finalMessage, completed = checkpoint, exportedFile = exported
            DispatchQueue.main.async {
                self?.running = false; self?.token = nil; self?.currentBatch = completed
                self?.results = completed.results; self?.upsert(completed)
                self?.status = finalText + (exportedFile == nil ? "" : " 已保存 Excel。")
                self?.lastExport = completed.excelPath.map { URL(fileURLWithPath: $0) }
            }
        }
    }
    private func upsert(_ record: BatchRecord) {
        history.removeAll { $0.id == record.id }
        history.append(record); history.sort { $0.updatedAt > $1.updatedAt }
    }
    func stop() { token?.stop(); status = "正在暂停，保存已取得的结果和续跑断点…" }
    func openOutputFolder() { openFolder(URL(fileURLWithPath: outputPath, isDirectory: true)) }
    func openHistoryFolder(_ record: BatchRecord) {
        let folder = record.excelPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            ?? URL(fileURLWithPath: outputPath, isDirectory: true)
        openFolder(folder)
    }
    private func openFolder(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(url) { status = "无法打开保存文件夹：\(url.path)" }
        } catch { status = "打开保存文件夹失败：\(error.localizedDescription)" }
    }
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
        guard !running, !updates.installing else { return }
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
        guard !running else { return }
        do {
            let url = try XLSXWriter.makeOutputURL(in: URL(fileURLWithPath: outputPath, isDirectory: true))
            try XLSXWriter.write(rows: results, to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastExport = url; status = "已保存 Excel：\(url.lastPathComponent)"
            if var record = currentBatch {
                record.excelPath = url.path; record.updatedAt = Date()
                try storage.save(record); currentBatch = record; upsert(record)
            }
        } catch { status = "Excel 或历史记录保存失败：\(error.localizedDescription)" }
    }
}
