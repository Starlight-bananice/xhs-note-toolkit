import AppKit
import SwiftUI

if CommandLine.arguments.contains("--self-test") {
    do { try SelfTests.run(); print("SELF-TEST PASSED"); exit(0) }
    catch { fputs("SELF-TEST FAILED: \(error)\n", stderr); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--batch"), index+1 < CommandLine.arguments.count {
    do {
        let args = CommandLine.arguments
        let text = try String(contentsOfFile: args[index+1], encoding: .utf8)
        var options = JobOptions()
        if args.contains("--status-only") { options.repair = false; options.metrics = false }
        if args.contains("--no-repair") { options.repair = false }
        let inputs = Links.parse(text)
        guard !inputs.isEmpty else { throw ToolkitError.message("没有有效的笔记链接。") }
        var rows = inputs.map { NoteResult(original: $0.original, noteID: $0.noteID) }
        let output: URL
        if let i = args.firstIndex(of: "--output"), i+1 < args.count { output = URL(fileURLWithPath: args[i+1]) }
        else { output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("result.json") }
        let stop = StopToken()
        defer {
            if let data = try? JSONEncoder().encode(rows) {
                try? data.write(to: output, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            }
        }
        try NoteRunner(stop: stop).run(inputs: inputs, options: options, adbPath: "", serial: "",
            progress: { i, row in rows[i] = row; print("\(i+1) \(row.status) 作者=\(row.author) 赞=\(row.likes) 藏=\(row.collects) 评=\(row.comments) \(row.detail)") },
            message: { print($0) })
        if let i = args.firstIndex(of: "--xlsx"), i+1 < args.count { try XLSXWriter.write(rows: rows, to: URL(fileURLWithPath: args[i+1])) }
        let data = try JSONEncoder().encode(rows)
        try data.write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(); self.model = model
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "小红书笔记助手"
        window.contentView = NSHostingView(rootView: AppView(model: model))
        window.minSize = NSSize(width: 1180, height: 820)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in model.updates.check() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.stop(); return .terminateNow
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate(); app.delegate = delegate
let menu = NSMenu()
let item = NSMenuItem(); menu.addItem(item)
let submenu = NSMenu(); item.submenu = submenu
submenu.addItem(withTitle: "退出小红书笔记助手", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let editItem = NSMenuItem(); menu.addItem(editItem)
let edit = NSMenu(title: "编辑"); editItem.submenu = edit
for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
    edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
}
app.mainMenu = menu
app.run()
