import Foundation

struct BatchRecord: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var input: String
    var options: JobOptions
    var results: [NoteResult]
    var state: String
    var excelPath: String?
    var remaining: Int { results.filter(\.needsResume).count }
    var completed: Int { results.count - remaining }
    var resumeIndices: [Int] { results.indices.filter { results[$0].needsResume } }

    init(input: String, options: JobOptions, results: [NoteResult]) {
        id = UUID(); createdAt = Date(); updatedAt = createdAt
        self.input = input; self.options = options; self.results = results
        state = "处理中"
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, input, options, results, state, excelPath
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        input = try values.decode(String.self, forKey: .input)
        options = try values.decode(JobOptions.self, forKey: .options)
        results = try values.decode([NoteResult].self, forKey: .results)
        state = try values.decodeIfPresent(String.self, forKey: .state) ?? (results.contains(where: \.needsResume) ? "已中断" : "已完成")
        excelPath = try values.decodeIfPresent(String.self, forKey: .excelPath)
    }

    func recovered() -> BatchRecord {
        var copy = self
        copy.results = results.map { row in
            var row = row
            if row.status == "处理中" { row.status = "未完成"; row.detail = "上次处理已中断，可继续处理。" }
            return row
        }
        if copy.state == "处理中" { copy.state = copy.remaining == 0 ? "已完成" : "已中断" }
        return copy
    }
}

struct BatchHistory {
    let directory: URL
    init(directory: URL = UpdateSession.directory) { self.directory = directory }
    var sessionURL: URL { directory.appendingPathComponent("session.json") }
    private var historyURL: URL { directory.appendingPathComponent("history", isDirectory: true) }

    func current() throws -> BatchRecord? {
        guard FileManager.default.fileExists(atPath: sessionURL.path) else { return nil }
        return try JSONDecoder().decode(BatchRecord.self, from: Data(contentsOf: sessionURL)).recovered()
    }
    func records() throws -> [BatchRecord] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                do { return try JSONDecoder().decode(BatchRecord.self, from: Data(contentsOf: url)).recovered() }
                catch { NSLog("无法读取一条本地历史记录：%@", error.localizedDescription); return nil }
            }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ record: BatchRecord) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: historyURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(record)
        for url in [historyURL.appendingPathComponent(record.id.uuidString + ".json"), sessionURL] {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
