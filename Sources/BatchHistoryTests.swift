import Foundation

enum BatchHistoryTests {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xhs-history-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BatchHistory(directory: root)
        let initial = try store.current()
        try SelfTests.expect(initial == nil, "首次启动没有断点")
        var options = JobOptions(); options.comments = false
        var record = BatchRecord(input: "原始输入", options: options,
                                 results: (0..<6).map { NoteResult(original: "https://xhslink.cn/o/test\($0)") })
        try store.save(record)
        let queued = try store.current()!
        try SelfTests.expect(queued.remaining == 6 && queued.state == "已中断", "连接前完整队列必须已落盘，可恢复所有未开始条目")

        record.results[0].status = "完成"; record.results[0].shareURL = "https://xhslink.cn/o/preserved"
        record.results[0].noteID = String(repeating: "a", count: 24)
        record.results[1].status = "已删除"
        record.results[2].status = "可访问"
        record.results[3].status = "重复笔记"
        record.results[4].status = "处理中"
        record.excelPath = root.appendingPathComponent("report.xlsx").path
        try store.save(record)
        let recovered = try BatchHistory(directory: root).current()!
        try SelfTests.expect(recovered.results[4].status == "未完成" && recovered.state == "已中断", "意外退出后的处理中项应恢复为可续跑")
        try SelfTests.expect(recovered.resumeIndices == [4, 5], "续跑必须跳过完成、可访问、已删除及重复条目")
        try SelfTests.expect(recovered.results[0].shareURL == record.results[0].shareURL && !recovered.options.comments,
                   "保留成功结果与原批次处理选项")
        try SelfTests.expect(recovered.id == record.id && recovered.excelPath == record.excelPath, "重启后保留批次身份与 Excel 路径")

        var next = BatchRecord(input: "下一批", options: JobOptions(), results: [])
        next.state = "已完成"; next.updatedAt = record.updatedAt.addingTimeInterval(10)
        try store.save(next)
        let records = try store.records()
        try SelfTests.expect(records.count == 2 && records[0].id == next.id, "新任务不覆盖之前的历史批次，按最近更新排序")
        try store.save(recovered)
        let savedRecords = try store.records()
        try SelfTests.expect(savedRecords.count == 2, "续跑保存应更新同一批次，不新增重复历史")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.sessionURL.path)
        try SelfTests.expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "含分享凭证的历史必须保存在私有文件中")

        let legacyStore = BatchHistory(directory: root.appendingPathComponent("legacy"))
        try FileManager.default.createDirectory(at: legacyStore.directory, withIntermediateDirectories: true)
        struct Legacy: Encodable { let input: String; let options: JobOptions; let results: [NoteResult] }
        try JSONEncoder().encode(Legacy(input: record.input, options: options, results: record.results))
            .write(to: legacyStore.sessionURL)
        let model = AppModel(storage: legacyStore, restoreUpdate: false)
        try SelfTests.expect(model.history.count == 1 && model.results.count == 6 && model.retryable,
                   "旧版单会话升级后应自动导入历史并可续跑")
        model.load(model.history[0])
        try SelfTests.expect(model.results[0].shareURL == record.results[0].shareURL && !model.options.comments,
                   "历史查看恢复完整结果与选项")
        let reopened = AppModel(storage: legacyStore, restoreUpdate: false)
        try SelfTests.expect(reopened.history.count == 1 && reopened.history[0].id == model.history[0].id,
                   "旧版迁移只导入一次，重启不得重复添加")
        let oldOptions = Data(#"{"repair":false,"metrics":false,"author":false,"likes":true,"collects":false,"comments":true,"skipExtraWait":true}"#.utf8)
        let migratedOptions = try JSONDecoder().decode(JobOptions.self, from: oldOptions)
        try SelfTests.expect(!migratedOptions.repair && !migratedOptions.metrics
                             && !migratedOptions.author && migratedOptions.likes && !migratedOptions.collects && migratedOptions.comments,
                             "移除等待开关后仍能读取带旧开关的记录，原采集选项不能丢失")
        let stop = StopToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { stop.stop() }
        let started = Date()
        do { try stop.pause(10); throw ToolkitError.message("倒计时未响应暂停") }
        catch ToolkitError.stopped { }
        try SelfTests.expect(Date().timeIntervalSince(started) < 1, "随机等待期间应及时响应暂停")
        print("History, legacy migration, checkpoint recovery, resume selection and pause checks passed")
    }
}
