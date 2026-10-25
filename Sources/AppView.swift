import AppKit
import SwiftUI

struct AppView: View {
    @ObservedObject var model: AppModel
    private let accent = Color(red: 0.94, green: 0.12, blue: 0.28)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "link.badge.plus").font(.system(size: 28, weight: .semibold)).foregroundColor(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("小红书笔记助手").font(.system(size: 23, weight: .semibold))
                    Text("安卓分享链接 · 互动数据 · 有效性检查").foregroundColor(.secondary)
                }
                Spacer()
                Text("0.1.0").foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("输入笔记链接").font(.headline)
                        Spacer()
                        Text("已识别 \(model.inputs.count) 篇笔记").foregroundColor(.secondary)
                        Button("粘贴") { model.input = NSPasteboard.general.string(forType: .string) ?? "" }.disabled(model.running)
                    }
                    TextEditor(text: $model.input).font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 125, maxHeight: 170).padding(6)
                        .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                        .disabled(model.running)
                    Text("支持官方短链、长链、分享文案混合粘贴；同一笔记自动去重。").font(.caption).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("本次处理").font(.headline)
                    Toggle("修复为安卓分享链接", isOn: $model.options.repair)
                    Toggle("抓取数据", isOn: $model.options.metrics)
                    HStack {
                        Toggle("作者", isOn: $model.options.author)
                        Toggle("点赞", isOn: $model.options.likes)
                    }.disabled(!model.options.metrics)
                    HStack {
                        Toggle("收藏", isOn: $model.options.collects)
                        Toggle("评论", isOn: $model.options.comments)
                    }.disabled(!model.options.metrics)
                    Text(model.options.statusOnly ? "当前仅判断笔记是否失效。" : "每条结果同时记录笔记状态。").font(.caption).foregroundColor(.secondary)
                    Button("仅检查有效性") { model.options.repair = false; model.options.metrics = false }
                }.frame(width: 245).disabled(model.running)
            }
            DisclosureGroup("连接与保存设置") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("安卓连接工具").frame(width: 90, alignment: .leading)
                        TextField("自动使用应用宝自带的 adb", text: $model.adbPath)
                        Button("选择…", action: model.chooseADB)
                    }
                    HStack {
                        Text("设备编号").frame(width: 90, alignment: .leading)
                        TextField("自动识别应用宝；多个设备时填写编号", text: $model.serial)
                        Button("检查连接", action: model.checkConnection)
                    }
                    HStack {
                        Text("Excel 保存到").frame(width: 90, alignment: .leading)
                        Text(model.outputPath).lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                        Spacer()
                        Button("选择文件夹…", action: model.chooseOutput)
                    }
                }.padding(.top, 8)
            }.disabled(model.running)
            HStack {
                Button("开始处理") { model.start() }.buttonStyle(.borderedProminent).tint(accent).disabled(model.running || model.inputs.isEmpty)
                Button("停止", action: model.stop).disabled(!model.running)
                Button("继续未完成") { model.start(resume: true) }.disabled(model.running || !model.retryable)
                Spacer()
                Button("复制分享链接") {
                    let rows = model.selection.isEmpty ? model.results : model.results.filter { model.selection.contains($0.id) }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rows.map(\.shareURL).filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
                }.disabled(model.running || !model.results.contains { !$0.shareURL.isEmpty })
                Button("导出 Excel", action: model.export).disabled(model.running || model.results.isEmpty)
                Button("打开 Excel") { if let url = model.lastExport { NSWorkspace.shared.open(url) } }.disabled(model.lastExport == nil)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if model.running { ProgressView().controlSize(.small) }
                    Text(model.status).lineLimit(3).textSelection(.enabled)
                    Spacer()
                    if !model.results.isEmpty { Text("\(model.finished) / \(model.results.count)").monospacedDigit().foregroundColor(.secondary) }
                }
                ProgressView(value: Double(model.finished), total: Double(max(1, model.results.count))).tint(accent)
            }
            Table(model.results, selection: $model.selection) {
                TableColumn("状态", value: \.status).width(min: 65, ideal: 82, max: 100)
                TableColumn("作者", value: \.author).width(min: 70, ideal: 100, max: 160)
                TableColumn("点赞", value: \.likes).width(55)
                TableColumn("收藏", value: \.collects).width(55)
                TableColumn("评论", value: \.comments).width(55)
                TableColumn("原始链接", value: \.original).width(min: 120, ideal: 200)
                TableColumn("安卓分享原链", value: \.shareURL).width(min: 140, ideal: 210)
                TableColumn("说明", value: \.detail).width(min: 130, ideal: 230)
            }.frame(minHeight: 180)
            Text("运行时保持应用宝内的小红书开启。链接由安卓客户端实际分享生成；未读取到的数据留空，0 会保留。").font(.caption).foregroundColor(.secondary)
        }.padding(22).frame(minWidth: 1040, minHeight: 720)
    }
}
