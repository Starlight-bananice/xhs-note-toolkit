import AppKit
import SwiftUI

private enum Palette {
    static let accent = Color(red: 0.93, green: 0.23, blue: 0.36)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.23)
    static let muted = Color(red: 0.48, green: 0.52, blue: 0.59)
    static let canvas = Color(red: 0.96, green: 0.965, blue: 0.975)
    static let line = Color(red: 0.89, green: 0.91, blue: 0.93)
    static let green = Color(red: 0.18, green: 0.57, blue: 0.44)
}

struct AppView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    init(model: AppModel) { self.model = model; self.updates = model.updates }
    private var busy: Bool { model.running || updates.installing }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 212)
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.showingSettings { settings }
                else {
                    HStack(alignment: .top, spacing: 16) {
                        inputCard
                        optionsCard.frame(width: 284)
                    }.fixedSize(horizontal: false, vertical: true)
                    actionBar
                    resultsCard
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("运行时保持应用宝中的小红书开启；分享链接由安卓客户端实际生成。")
                        Spacer()
                    }.font(.system(size: 10)).foregroundColor(Palette.muted)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Palette.canvas)
        }.preferredColorScheme(.light).tint(Palette.accent)
            .frame(minWidth: 1140, minHeight: 750)
    }

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(size: NSSize(width: 64, height: 64))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: appIcon).resizable().frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("小红书").font(.system(size: 17, weight: .semibold))
                    Text("笔记助手").font(.system(size: 11)).foregroundColor(.white.opacity(0.52))
                }
            }.foregroundColor(.white).padding(.top, 25).padding(.bottom, 35)
            Text("工作空间").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 14).padding(.bottom, 12)
            navButton("笔记工作台", icon: "square.grid.2x2", settings: false)
            navButton("连接与保存", icon: "slider.horizontal.3", settings: true).padding(.top, 7)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "apps.iphone").foregroundColor(Color(red: 0.99, green: 0.63, blue: 0.64))
                    Text("腾讯应用宝").font(.system(size: 11, weight: .medium))
                }
                Text("使用安卓小红书处理笔记\n无需操作 Mac 鼠标")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.46)).lineSpacing(4)
            }.foregroundColor(.white.opacity(0.85)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
            Rectangle().fill(.white.opacity(0.09)).frame(height: 1).padding(.vertical, 18)
            HStack(spacing: 7) {
                Text("v\(updates.version)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.62))
                Spacer(minLength: 0)
                Button {
                    Task { @MainActor in updates.click(model: model) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .semibold))
                        Text(updates.label).font(.system(size: 10, weight: .medium))
                    }.foregroundColor(updates.available == nil ? .white.opacity(0.86) : .white)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(updates.available == nil ? Color.white.opacity(0.09) : Palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(model.running || updates.busy).help(updates.detail)
            }
            HStack {
                Text(updates.detail).font(.system(size: 9)).foregroundColor(.white.opacity(0.36)).lineLimit(2)
                Spacer(minLength: 0)
                Link(destination: AppUpdater.releasePage) { Image(systemName: "arrow.up.right.square").font(.system(size: 10)) }
                    .foregroundColor(.white.opacity(0.5)).help("打开 GitHub 正式版下载页")
            }.frame(minHeight: 28, alignment: .top).padding(.top, 8)
        }.padding(.horizontal, 16).padding(.bottom, 17)
            .background(LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.23), Color(red: 0.09, green: 0.12, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func navButton(_ title: String, icon: String, settings: Bool) -> some View {
        let selected = model.showingSettings == settings
        return Button { model.showingSettings = settings } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
                if selected { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
            }.foregroundColor(selected ? .white : .white.opacity(0.48)).padding(.horizontal, 13).padding(.vertical, 13)
                .background(selected ? Color.white.opacity(0.09) : .clear).clipShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.showingSettings ? "连接与保存" : "笔记工作台")
                    .font(.system(size: 25, weight: .semibold)).foregroundColor(Palette.ink)
                Text(model.showingSettings ? "管理应用宝连接和结果文件的位置。" : "修复分享链接，收集互动数据，检查笔记状态。")
                    .font(.system(size: 11)).foregroundColor(Palette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Palette.green.opacity(0.7)).frame(width: 5, height: 5)
                Text("安卓客户端").font(.system(size: 10, weight: .medium))
            }.foregroundColor(Palette.muted).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white).clipShape(Capsule()).overlay(Capsule().stroke(Palette.line))
        }.padding(.bottom, 4)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("01", "添加笔记链接")
                Spacer()
                Text("\(model.inputs.count) 篇笔记").font(.system(size: 10, weight: .medium)).foregroundColor(Palette.accent)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(Palette.accent.opacity(0.07)).clipShape(Capsule())
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.input).font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(9).disabled(busy)
                if model.input.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把笔记链接粘贴到这里").foregroundColor(Palette.muted)
                        Text("支持官方短链、长链或完整分享文案，一行一条。")
                            .foregroundColor(Palette.muted.opacity(0.7))
                    }.font(.system(size: 11)).padding(15).allowsHitTesting(false)
                }
            }.frame(height: 119).background(Palette.canvas.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line.opacity(0.85)))
            HStack(spacing: 12) {
                Button {
                    model.input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("从剪贴板粘贴", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundColor(Palette.ink).disabled(busy)
                Button("清空") { model.input = "" }.buttonStyle(.plain).font(.system(size: 10))
                    .foregroundColor(Palette.muted).disabled(busy || model.input.isEmpty)
                Spacer()
                Label("按笔记去重", systemImage: "checkmark.circle").font(.system(size: 9)).foregroundColor(Palette.muted)
            }.frame(height: 19)
        }.padding(17).card()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("02", "选择处理内容")
            Toggle(isOn: $model.options.repair) {
                Label("修复分享链接", systemImage: "link").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.ink)
            }.toggleStyle(.switch).controlSize(.small)
            Toggle(isOn: $model.options.metrics) {
                Label("采集笔记数据", systemImage: "chart.bar.xaxis").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.ink)
            }.toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 6) {
                fieldChip("作者", value: $model.options.author)
                fieldChip("点赞", value: $model.options.likes)
                fieldChip("收藏", value: $model.options.collects)
                fieldChip("评论", value: $model.options.comments)
            }.disabled(!model.options.metrics).opacity(model.options.metrics ? 1 : 0.4)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                Text(model.options.statusOnly ? "当前仅检查有效性" : "同时记录笔记状态").font(.system(size: 9)).foregroundColor(Palette.muted)
                Spacer(minLength: 0)
                Button("仅查有效性") { model.options.repair = false; model.options.metrics = false }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundColor(Palette.accent)
            }.frame(height: 23)
        }.padding(17).card().disabled(busy)
    }

    private func fieldChip(_ title: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 3) {
                if value.wrappedValue { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                Text(title).font(.system(size: 10, weight: .medium))
            }.foregroundColor(value.wrappedValue ? Palette.accent : Palette.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(value.wrappedValue ? Palette.accent.opacity(0.07) : Palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel("采集\(title)").accessibilityValue(value.wrappedValue ? "已选择" : "未选择")
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Button { model.start() } label: {
                    Label("开始处理", systemImage: "play.fill").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(Palette.accent).disabled(busy || model.inputs.isEmpty)
                Button { model.stop() } label: { Label("停止", systemImage: "stop.fill") }
                    .font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(Palette.muted).disabled(!model.running)
                Button("继续未完成") { model.start(resume: true) }.font(.system(size: 10))
                    .buttonStyle(.borderless).foregroundColor(Palette.ink).disabled(busy || !model.retryable)
                Spacer()
                if model.running { ProgressView().controlSize(.small) }
                Text(model.results.isEmpty ? "准备就绪" : "\(model.finished) / \(model.results.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Palette.muted)
            }
            ProgressView(value: Double(model.finished), total: Double(max(1, model.results.count))).tint(Palette.accent)
            Text(model.status).font(.system(size: 10)).foregroundColor(Palette.muted).lineLimit(2).textSelection(.enabled)
        }.padding(.horizontal, 17).padding(.vertical, 14).card()
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("处理结果").font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.ink)
                Text("\(model.results.count)").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Palette.muted).padding(.horizontal, 7).padding(.vertical, 3).background(Palette.canvas).clipShape(Capsule())
                Spacer()
                Button { copyLinks() } label: { Label("复制链接", systemImage: "doc.on.doc") }
                    .disabled(busy || !model.results.contains { !$0.shareURL.isEmpty })
                Button { model.export() } label: { Label("导出 Excel", systemImage: "square.and.arrow.up") }
                    .disabled(busy || model.results.isEmpty)
                Button { if let url = model.lastExport { NSWorkspace.shared.open(url) } } label: { Image(systemName: "arrow.up.right.square") }
                    .disabled(model.lastExport == nil).help("打开最近的 Excel")
            }.font(.system(size: 10)).buttonStyle(.borderless).foregroundColor(Palette.muted).padding(.horizontal, 17).padding(.vertical, 14)
            Rectangle().fill(Palette.line).frame(height: 1)
            Table(model.results, selection: $model.selection) {
                TableColumn("状态") { row in
                    HStack(spacing: 5) {
                        Circle().fill(statusColor(row.status)).frame(width: 5, height: 5)
                        Text(row.status).font(.system(size: 10, weight: .medium)).foregroundColor(statusColor(row.status))
                    }
                }.width(min: 75, ideal: 83, max: 100)
                TableColumn("作者", value: \.author).width(min: 65, ideal: 86, max: 130)
                TableColumn("点赞", value: \.likes).width(43)
                TableColumn("收藏", value: \.collects).width(43)
                TableColumn("评论", value: \.comments).width(43)
                TableColumn("原始链接") { row in Text(row.original).lineLimit(1).help(row.original) }.width(min: 100, ideal: 160)
                TableColumn("安卓分享链接") { row in Text(row.shareURL).lineLimit(1).foregroundColor(Palette.accent).help(row.shareURL) }.width(min: 120, ideal: 180)
                TableColumn("说明") { row in Text(row.detail).lineLimit(1).foregroundColor(Palette.muted).help(row.detail) }.width(min: 90, ideal: 140)
            }.font(.system(size: 10)).frame(minHeight: 150, maxHeight: .infinity)
                .overlay {
                    if model.results.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "tray").font(.system(size: 27, weight: .light)).foregroundColor(Palette.muted.opacity(0.35))
                            Text("结果会出现在这里").font(.system(size: 12, weight: .medium)).foregroundColor(Palette.ink.opacity(0.6))
                            Text("开始处理后，逐条查看分享链接与笔记数据。")
                                .font(.system(size: 10)).foregroundColor(Palette.muted)
                        }.allowsHitTesting(false)
                    }
                }
        }.card()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                sectionTitle("01", "结果保存位置")
                Text("每次处理结束后，自动将结果保存为 Excel。").font(.system(size: 11)).foregroundColor(Palette.muted)
                HStack {
                    Image(systemName: "folder").foregroundColor(Palette.accent)
                    Text(model.outputPath).font(.system(size: 11)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("选择文件夹…", action: model.chooseOutput)
                }.padding(12).background(Palette.canvas).clipShape(RoundedRectangle(cornerRadius: 8))
            }.padding(20).card()
            VStack(alignment: .leading, spacing: 16) {
                HStack { sectionTitle("02", "应用宝连接"); Spacer(); Button("检查连接", action: model.checkConnection) }
                Text("先在腾讯应用宝中打开并登录小红书。软件会自动识别连接和窗口。").font(.system(size: 11)).foregroundColor(Palette.muted)
                DisclosureGroup("高级连接设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("连接工具").frame(width: 70, alignment: .leading)
                            TextField("自动使用应用宝自带的 adb", text: $model.adbPath)
                            Button("选择…", action: model.chooseADB)
                        }
                        HStack {
                            Text("设备编号").frame(width: 70, alignment: .leading)
                            TextField("自动识别；连接多个设备时填写", text: $model.serial)
                        }
                    }.font(.system(size: 11)).padding(.top, 12)
                }.font(.system(size: 11)).foregroundColor(Palette.muted)
            }.padding(20).card()
            HStack(spacing: 8) {
                if model.running { ProgressView().controlSize(.small) }
                Text(model.status).font(.system(size: 11)).foregroundColor(Palette.muted).textSelection(.enabled)
            }.padding(.horizontal, 4)
            Spacer()
        }.disabled(busy)
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Palette.accent)
                .padding(.horizontal, 6).padding(.vertical, 4).background(Palette.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.ink)
        }
    }
    private func statusColor(_ state: String) -> Color {
        switch state {
        case "完成", "可访问": return Palette.green
        case "已删除": return Palette.muted
        case "处理失败", "访问受限": return Palette.accent
        case "处理中", "需验证", "待核验", "部分完成": return Color(red: 0.72, green: 0.49, blue: 0.12)
        default: return Palette.muted
        }
    }
    private func copyLinks() {
        let rows = model.selection.isEmpty ? model.results : model.results.filter { model.selection.contains($0.id) }
        let links = rows.map(\.shareURL).filter { !$0.isEmpty }.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(links, forType: .string)
    }
}

private extension View {
    func card() -> some View {
        background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line.opacity(0.75)))
    }
}
