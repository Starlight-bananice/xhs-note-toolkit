import Foundation

struct UINode {
    var text: String
    var description: String
    var className: String
    var package: String
    var bounds: CGRect
    var clickable: Bool
    var parent: Int?
    var display: Int
    var label: String { [text, description].filter { !$0.isEmpty }.joined(separator: " ") }
}

final class Page: NSObject, XMLParserDelegate {
    var nodes = [UINode]()
    private var stack = [Int]()
    private var display = 0
    static func read(_ xml: String) throws -> Page {
        guard let start = xml.range(of: "<?xml"), let end = xml.range(of: "</hierarchy>", options: .backwards) else {
            throw ToolkitError.message("没有取得安卓界面结构，请重新连接应用宝。")
        }
        let page = Page()
        let parser = XMLParser(data: Data(xml[start.lowerBound..<end.upperBound].utf8))
        parser.delegate = page
        guard parser.parse(), !page.nodes.isEmpty else { throw ToolkitError.message("没有找到小红书可读取的窗口。请先打开小红书。") }
        return page
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String]) {
        if elementName == "window" { display = Int(a["display"] ?? "0") ?? 0 }
        guard elementName == "node" else { return }
        let raw = a["bounds"] ?? ""
        let numbers = raw.split(whereSeparator: { !$0.isNumber && $0 != "-" }).compactMap { Double($0) }
        let rect = numbers.count == 4 ? CGRect(x: numbers[0], y: numbers[1], width: max(0, numbers[2]-numbers[0]), height: max(0, numbers[3]-numbers[1])) : .zero
        nodes.append(UINode(text: a["text"] ?? "", description: a["content-desc"] ?? "", className: a["class"] ?? "",
                            package: a["package"] ?? "", bounds: rect, clickable: a["clickable"] == "true", parent: stack.last, display: display))
        stack.append(nodes.count-1)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "node" { _ = stack.popLast() }
    }
    var labels: [String] { nodes.filter { $0.package == "com.xingin.xhs" && !$0.bounds.isEmpty }.map(\.label).filter { !$0.isEmpty } }
    var deletedHint: String? {
        let markers = ["当前内容无法展示", "笔记已删除", "笔记不存在", "内容已删除", "内容不存在"]
        return labels.first { value in markers.contains(where: { value == $0 || value.hasPrefix($0 + "，") }) }
    }
    var restriction: String? {
        let markers = ["当前账号存在异常", "安全限制", "访问频繁", "请完成验证", "请先登录", "登录后查看"]
        return labels.first { value in markers.contains(where: value.contains) }
    }
    var isHome: Bool { labels.contains("首页") && labels.contains("发现") && labels.contains("市集") }
    var isAuthorProfile: Bool {
        deletedHint == nil && !isHome && !isReadableNote
            && find(exact: ["粉丝"]) != nil && find(exact: ["关注", "已关注", "互相关注"]) != nil
            && find(exact: ["笔记", "获赞与收藏"]) != nil
    }
    var isLoginPage: Bool {
        !isHome && !isReadableNote && find(exact: ["手机号登录", "一键登录", "验证码登录"]) != nil
    }
    func find(exact labels: [String]) -> Int? {
        nodes.indices.first { i in
            let n = nodes[i]
            return n.package == "com.xingin.xhs" && !n.bounds.isEmpty && (labels.contains(n.text) || labels.contains(n.description))
        }
    }
    func clickable(_ index: Int) -> UINode? {
        var current: Int? = index
        while let i = current {
            let n = nodes[i]
            if n.clickable && !n.bounds.isEmpty { return n }
            current = n.parent
        }
        return nodes[index].bounds.isEmpty ? nil : nodes[index]
    }
    var screen: CGRect { nodes.first?.bounds ?? .zero }
    var author: String {
        if let n = nodes.first(where: { $0.description.hasPrefix("作者") && $0.description.count > 2 && !$0.bounds.isEmpty }) {
            return String(n.description.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // In photo notes, the header exposes the nickname beside the follow button.
        if let follow = find(exact: ["关注", "已关注", "互相关注"]) {
            let f = nodes[follow].bounds
            let names = nodes.filter {
                $0.className.hasSuffix("TextView") && !$0.text.isEmpty && $0.text != "关注"
                && abs($0.bounds.midY-f.midY) < max(50, f.height) && $0.bounds.maxX < f.minX
                && $0.bounds.minY < screen.height * 0.2 && !$0.bounds.isEmpty
            }
            return names.sorted(by: { $0.bounds.maxX > $1.bounds.maxX }).first?.text ?? ""
        }
        return ""
    }
    var isNote: Bool {
        !isHome && !author.isEmpty && (nodes.contains { $0.description.hasPrefix("收藏") }
            || labels.contains("说点什么...") || labels.contains("说点什么…"))
    }
    var isReadableNote: Bool {
        if isNote { return true }
        // Guest pages may omit the author header. Require actual media and the note toolbar,
        // rather than treating a login prompt or a partial loading page as a readable note.
        let media = nodes.contains {
            $0.package == "com.xingin.xhs" && !$0.bounds.isEmpty
                && ($0.description.hasPrefix("图片,第") || $0.className.hasSuffix("VideoView")
                    || $0.className.hasSuffix("SurfaceView") || $0.className.hasSuffix("TextureView"))
        }
        let toolbar = nodes.contains {
            $0.package == "com.xingin.xhs" && !$0.bounds.isEmpty
                && $0.bounds.midY > screen.height * 0.75 && $0.description.hasPrefix("收藏")
        }
        return !isHome && media && toolbar && find(exact: ["说点什么...", "说点什么…"]) != nil
    }
    func metric(_ prefix: String) -> String {
        for n in nodes where !n.bounds.isEmpty && n.bounds.midY > screen.height * 0.75 {
            if let value = Links.capture(n.description, "^(?:已)?\(prefix)\\s*([0-9]+(?:\\.[0-9]+)?[万亿千wWkK]?\\+?)$") { return value }
        }
        return ""
    }
    var metrics: (likes: String, collects: String, comments: String) {
        let collect = metric("收藏"), comment = metric("评论")
        var like = metric("点赞")
        if like.isEmpty { like = metric("赞") }
        if like.isEmpty {
            // The Android video toolbar's like control has no accessibility label.
            // Read its numeric child only among direct siblings of the collect button.
            if let c = nodes.indices.first(where: { nodes[$0].description.hasPrefix("收藏") && nodes[$0].bounds.midY > screen.height * 0.75 }),
               let parent = nodes[c].parent {
                let siblings = nodes.indices.filter { nodes[$0].parent == parent && nodes[$0].clickable && nodes[$0].description.isEmpty }
                let candidates = siblings.compactMap { i -> String? in
                    nodes.indices.filter { nodes[$0].parent == i }.compactMap { child -> String? in
                        let value = nodes[child].text
                        return Links.capture(value, #"^([0-9]+(?:\.[0-9]+)?[万亿千wWkK]?\+?)$"#)
                    }.first
                }
                if candidates.count == 1 { like = candidates[0] }
            }
        }
        return (like, collect, comment)
    }
    var shareButton: UINode? {
        let labeled = nodes.indices.first { i in
            nodes[i].clickable && !nodes[i].bounds.isEmpty &&
            Links.capture(nodes[i].description, #"^(分享(?:笔记)?)(?:\s*[0-9.万亿千wWkK+]+)?$"#) != nil
        }
        if let i = labeled { return nodes[i] }
        guard isNote else { return nil }
        let topRight = nodes.filter {
            $0.clickable && $0.className.hasSuffix("ImageView") && $0.label.isEmpty
                && $0.bounds.width > 20 && $0.bounds.height > 20
                && $0.bounds.midX > screen.width * 0.88 && $0.bounds.midY < screen.height * 0.18
        }
        return topRight.sorted(by: { $0.bounds.midX > $1.bounds.midX }).first
    }
    var shareStrip: CGRect? {
        guard labels.contains("分享至") || labels.contains("分享到") else { return nil }
        // Scroll only the tools strip containing known share actions, never the private-message row.
        for i in nodes.indices where ["生成分享图", "引用发笔记", "建群分享", "保存到相册", "倍速播放", "举报"].contains(nodes[i].text) {
            var current = nodes[i].parent
            while let index = current {
                let node = nodes[index]
                if node.className.contains("HorizontalScrollView") || (node.className.contains("RecyclerView") && node.bounds.width > node.bounds.height*2) {
                    return node.bounds
                }
                current = node.parent
            }
        }
        return nil
    }
}
