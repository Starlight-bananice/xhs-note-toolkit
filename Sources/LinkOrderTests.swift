import Foundation

enum LinkOrderTests {
    static func run() throws {
        let a = "https://www.xiaohongshu.com/discovery/item/aaaaaaaaaaaaaaaaaaaaaaaa"
        let b = "https://www.xiaohongshu.com/explore/bbbbbbbbbbbbbbbbbbbbbbbb"
        let short = "https://xhslink.cn/o/repeated"
        let variant = "https://www.xiaohongshu.com/explore/aaaaaaaaaaaaaaaaaaaaaaaa?xsec_token=test%3D&xsec_source=app_share"
        let originals = [a, short, b, a, variant, short, b]
        let text = originals.joined(separator: "\n")
        let parsed = Links.parse(text)
        try SelfTests.expect(parsed.map(\.original) == originals,
                             "输入解析必须保留重复长链、重复短链、同笔记不同参数及全部输入顺序")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xhs-order-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BatchHistory(directory: root)
        var record = BatchRecord(input: text, options: JobOptions(),
                                 results: parsed.map { NoteResult(original: $0.original, noteID: $0.noteID) })
        try SelfTests.expect(Set(record.results.map(\.id)).count == originals.count,
                             "同一输入重复出现时仍须是独立结果行")
        record.results[0].status = "完成"; record.results[0].shareURL = "https://xhslink.cn/o/result-a"
        record.results[1].status = "已删除"
        record.results[2].status = "完成"; record.results[2].shareURL = "https://xhslink.cn/o/result-b"
        record.results[3].status = "未完成"
        record.results[5].status = "重复笔记" // A row skipped by an older version.
        record.results[5].noteID = parsed[0].noteID
        record.results[6].status = "处理中"
        try store.save(record)
        var recovered = try store.current()!
        try SelfTests.expect(recovered.results.map(\.original) == originals && recovered.resumeIndices == [3, 4, 5, 6],
                             "续跑按行保留顺序，前面的同笔记已完成不能吞掉后面的重复行")
        try SelfTests.expect(recovered.results[5].status == "未完成" && recovered.results[6].status == "未完成",
                             "旧版跳过的重复行和中断行均可继续处理")
        // Checkpointing a later occurrence must keep the earlier occurrence and every empty slot.
        recovered.results[3].status = "完成"; recovered.results[3].shareURL = recovered.results[0].shareURL
        try store.save(recovered)
        let reopened = try store.current()!
        try SelfTests.expect(reopened.results.map(\.original) == originals && reopened.resumeIndices == [4, 5, 6]
                             && reopened.results[0].shareURL == record.results[0].shareURL,
                             "保存和重开断点不能重排或覆盖重复链接的其他行")
        var oldCompleted = record
        oldCompleted.state = "已完成"
        try SelfTests.expect(oldCompleted.recovered().state == "待续跑",
                             "旧版含跳过重复行的已完成批次应允许补跑")
        let model = AppModel(storage: store, restoreUpdate: false)
        let expectedLinks = reopened.results.map(\.shareURL)
        try SelfTests.expect(model.inputs.map(\.original) == originals
                             && model.linksForCopy.components(separatedBy: "\n") == expectedLinks,
                             "界面计数与复制结果保留全部重复项、中间及末尾的空行")
        model.selection = [model.results[3].id, model.results[1].id, model.results[0].id]
        try SelfTests.expect(model.linksForCopy.components(separatedBy: "\n")
                             == [expectedLinks[0], expectedLinks[1], expectedLinks[3]],
                             "选择结果复制时仍按原结果顺序，保留重复项和空行")
        let excel = root.appendingPathComponent("ordered.xlsx")
        try XLSXWriter.write(rows: reopened.results, to: excel)
        let xml = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"),
                                        ["-p", excel.path, "xl/worksheets/sheet1.xml"])
        try SelfTests.expect(xml.contains("A1:M8"), "Excel 必须输出七条记录，不能合并重复或删除空结果行")
        for index in originals.indices {
            for (column, value) in [("B", originals[index]), ("E", expectedLinks[index])] {
                let cell = Links.capture(xml, "<c r=\"\(column)\(index+2)\"[^>]*><is><t[^>]*>(.*?)</t></is></c>")
                try SelfTests.expect(cell?.replacingOccurrences(of: "&amp;", with: "&") == value,
                                     "Excel 原始链接和分享链接须在各自的对应行，不得去重或前移")
            }
        }
        print("Repeated links, row ordering, resume, clipboard empty slots and Excel alignment checks passed")
    }
}
