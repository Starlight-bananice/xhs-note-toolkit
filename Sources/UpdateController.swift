import AppKit
import Combine
import Foundation

final class UpdateController: ObservableObject {
    @Published var label = "检查更新"
    @Published var detail = "从 GitHub 获取正式版本"
    @Published var busy = false
    @Published var installing = false
    @Published var available: AppRelease?
    var version: String { AppUpdater.currentVersion }

    @MainActor func check() {
        guard !busy else { return }
        busy = true; label = "检查中…"
        Task { @MainActor [self] in
            defer { busy = false }
            do {
                available = try await AppUpdater.check(currentVersion: version)
                label = available.map { "更新到 v\($0.version)" } ?? "已是最新版"
                detail = available == nil ? "当前版本已是最新正式版" : "点击下载、安装并重新打开"
            } catch {
                label = "重试检查"; detail = error.localizedDescription
            }
        }
    }

    @MainActor func click(model: AppModel) {
        guard !model.running, !busy else { return }
        guard let release = available else { check(); return }
        busy = true; installing = true
        Task { @MainActor [self] in
            var prepared: PreparedAppUpdate?
            var snapshotSaved = false
            do {
                let update = try await AppUpdater.prepare(release) { [weak self] progress in
                    DispatchQueue.main.async { self?.label = progress }
                }
                prepared = update
                try UpdateSession(input: model.input, options: model.options, results: model.results,
                                  status: model.status, excelPath: model.lastExport?.path).save()
                snapshotSaved = true
                if FileManager.default.fileExists(atPath: UpdateSession.failureFile.path) {
                    try FileManager.default.removeItem(at: UpdateSession.failureFile)
                }
                try AppUpdater.launchInstaller(update, parentPID: ProcessInfo.processInfo.processIdentifier)
                label = "正在重启…"; detail = "输入和结果将在新版中恢复"
                NSApp.terminate(nil)
            } catch {
                if snapshotSaved { try? FileManager.default.removeItem(at: UpdateSession.file) }
                if let prepared { try? FileManager.default.removeItem(at: prepared.directory) }
                busy = false; installing = false; label = "重试更新"; detail = error.localizedDescription
            }
        }
    }
}
