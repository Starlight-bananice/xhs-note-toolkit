import Foundation

enum XLSXWriterError: LocalizedError {
    case noDesktopDirectory
    case outputAlreadyExists
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDesktopDirectory:
            return "无法定位桌面文件夹。"
        case .outputAlreadyExists:
            return "目标 Excel 文件已经存在。"
        case .zipFailed(let message):
            return "生成 Excel 文件失败：\(message)"
        }
    }
}

enum XLSXWriter {
    static func makeOutputURL(in directory: URL, at date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: date)
        var sequence = 1
        var candidate: URL
        repeat {
            let suffix = sequence == 1 ? "" : "_\(sequence)"
            candidate = directory.appendingPathComponent("\(stamp)\(suffix)_小红书笔记结果.xlsx")
            sequence += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    static func write(rows: [NoteResult], to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw XLSXWriterError.outputAlreadyExists
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("xhs-xlsx-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try writePackageFiles(rows: rows, root: temporaryDirectory)

        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = temporaryDirectory
        process.arguments = [
            "-q", "-X", "-r", destinationURL.path,
            "[Content_Types].xml", "_rels", "docProps", "xl"
        ]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "zip 退出码 \(process.terminationStatus)"
            throw XLSXWriterError.zipFailed(message)
        }
    }

    private static func writePackageFiles(rows: [NoteResult], root: URL) throws {
        let fileManager = FileManager.default
        let directories = [
            "_rels",
            "docProps",
            "xl",
            "xl/_rels",
            "xl/worksheets"
        ]
        for directory in directories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", rootRelationshipsXML),
            ("docProps/app.xml", appPropertiesXML),
            ("docProps/core.xml", corePropertiesXML),
            ("xl/workbook.xml", workbookXML),
            ("xl/_rels/workbook.xml.rels", workbookRelationshipsXML),
            ("xl/styles.xml", stylesXML),
            ("xl/worksheets/sheet1.xml", worksheetXML(rows: rows))
        ]

        for (path, text) in files {
            try Data(text.utf8).write(to: root.appendingPathComponent(path), options: .atomic)
        }
    }

    private static func worksheetXML(rows: [NoteResult]) -> String {
        let headers = ["序号", "原始链接", "笔记 ID", "状态", "安卓分享原链", "展开后的链接", "作者", "点赞", "收藏", "评论", "说明", "处理时间", "原始分享文案"]
        let head = headers.enumerated().map { inlineCell(column: columnName($0.offset+1), row: 1, value: $0.element, style: 1) }.joined()
        let body = rows.enumerated().map { index, item in
            let values = [String(index+1), item.original, item.noteID, item.status, item.shareURL, item.expandedURL,
                          item.author, item.likes, item.collects, item.comments, item.detail, item.processedAt, item.shareText]
            let cells = values.enumerated().map { offset, value in
                inlineCell(column: columnName(offset+1), row: index+2, value: value, style: 5)
            }.joined()
            return "<row r=\"\(index+2)\" ht=\"40\" customHeight=\"1\">\(cells)</row>"
        }.joined()
        let last = max(1, rows.count+1)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <dimension ref="A1:M\(last)"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <cols><col min="1" max="1" width="8" customWidth="1"/>
        <col min="2" max="3" width="38" customWidth="1"/>
        <col min="4" max="4" width="14" customWidth="1"/>
        <col min="5" max="6" width="62" customWidth="1"/>
        <col min="7" max="7" width="24" customWidth="1"/>
        <col min="8" max="10" width="12" customWidth="1"/>
        <col min="11" max="13" width="42" customWidth="1"/></cols>
        <sheetData><row r="1" ht="26" customHeight="1">\(head)</row>\(body)</sheetData>
        <autoFilter ref="A1:M\(last)"/>
        </worksheet>
        """
    }

    private static func inlineCell(column: String, row: Int, value: String, style: Int) -> String {
        #"<c r="\#(column)\#(row)" t="inlineStr" s="\#(style)"><is><t xml:space="preserve">\#(escapeXML(value))</t></is></c>"#
    }

    private static func numberCell(column: String, row: Int, value: Int) -> String {
        #"<c r="\#(column)\#(row)"><v>\#(value)</v></c>"#
    }

    private static func dateCell(column: String, row: Int, value: Date, style: Int) -> String {
        let localOffset = TimeInterval(TimeZone.current.secondsFromGMT(for: value))
        let serial = (value.timeIntervalSince1970 + localOffset) / 86_400 + 25_569
        return #"<c r="\#(column)\#(row)" s="\#(style)"><v>\#(String(format: "%.10f", serial))</v></c>"#
    }

    private static func columnName(_ index: Int) -> String {
        var value = index
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="24000" windowHeight="12000"/></bookViews>
      <sheets><sheet name="转换结果" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><name val="Arial"/><family val="2"/></font>
        <font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/><family val="2"/></font>
      </fonts>
      <fills count="6">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFE2F0D9"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFCE4D6"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/></numFmts>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="7">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    private static let appPropertiesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>小红书笔记助手</Application>
    </Properties>
    """

    private static var corePropertiesXML: String {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>小红书笔记结果</dc:title>
          <dc:creator>小红书笔记助手</dc:creator>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }
}
