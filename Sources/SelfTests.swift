import Foundation

enum SelfTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ToolkitError.message(message) }
    }
    static func run() throws {
        try BatchHistoryTests.run()
        try NotePacingTests.run()
        try expect(runAppUpdaterTests(), "更新检查、安装包校验及安装回退测试")
        let id = "aaaaaaaaaaaaaaaaaaaaaaaa"
        let url = "https://www.xiaohongshu.com/explore/\(id)?xsec_token=A%2BB%3D&xsec_source=app_share"
        let mixed = "标题 \(url)\nhttps://www.xiaohongshu.com/discovery/item/\(id)\n短链 http://xhslink.cn/a/test\nhttps://www.xiaohongshu.com/user/profile/bbbbbbbbbbbbbbbbbbbbbbbb\nhttps://evil.example/explore/\(id)"
        let inputs = Links.parse(mixed)
        try expect(inputs.count == 2, "短长链、分享文案、主页排除与笔记去重")
        try expect(inputs[0].original == url, "不能丢弃原链的分享参数")
        try expect(inputs[1].noteID.isEmpty, "短链必须展开后才取得笔记 ID")
        try expect(!Links.official(URL(string: "https://xiaohongshu.com.evil.example/explore/\(id)")!), "仿冒域名不得通过")
        try expect(!Links.official(URL(string: "https://user:pass@www.xiaohongshu.com/explore/\(id)")!), "不得处理携带凭据的 URL")
        try expect(Links.noteID(URL(string: url)!) == id, "标准笔记解析")
        try expect(Links.isVideo(URL(string: url + "&type=video")!), "分享长链的视频类型识别")
        let redirect = RedirectGuard()
        let short = URL(string: "https://xhslink.cn/o/test")!
        let task = URLSession.shared.dataTask(with: short)
        let response = HTTPURLResponse(url: short, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: [:])!
        var followed = true
        redirect.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: url)!)) { followed = $0 != nil }
        try expect(!followed && redirect.destination?.absoluteString == url, "必须保留第一次重定向得到的笔记链接，不能跟随到风控页后丢掉凭证")
        let denied = RedirectGuard()
        denied.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                          newRequest: URLRequest(url: URL(string: "https://evil.example/")!)) { followed = $0 != nil }
        try expect(!followed && denied.blocked, "短链不得跟随到非官方域名")
        task.cancel()
        try expect(ProcessRunner.quote("a'b $x; z") == "'a'\\''b $x; z'", "远端参数必须逐个安全引用")
        try expect(AndroidSession.displayID("Window #0 com.other/.Main\n mDisplayId=0\nWindow #1 com.xingin.xhs/.Main\n mDisplayId=3") == 3, "不能固定使用安卓主显示器")
        let video = try Page.read("""
        <?xml version="1.0"?><hierarchy><window display="3">
        <node package="com.xingin.xhs" bounds="[0,0][2560,1600]">
        <node package="com.xingin.xhs" class="android.widget.Button" content-desc="作者测试作者" bounds="[20,1000][300,1100]"/>
        <node package="com.xingin.xhs" bounds="[1800,1487][2560,1600]">
        <node package="com.xingin.xhs" clickable="true" content-desc="分享12" bounds="[1800,1487][1950,1600]"/>
        <node package="com.xingin.xhs" clickable="true" bounds="[1950,1487][2100,1600]">
        <node package="com.xingin.xhs" text="0" bounds="[2000,1520][2050,1580]"/></node>
        <node package="com.xingin.xhs" clickable="true" content-desc="收藏347" bounds="[2100,1487][2300,1600]"/>
        <node package="com.xingin.xhs" clickable="true" content-desc="评论 168" bounds="[2300,1487][2550,1600]"/>
        </node><node package="com.xingin.xhs" text="9999" bounds="[0,500][200,550]"/>
        </node></window></hierarchy>
        """)
        try expect(video.isNote && video.author == "测试作者", "视频详情与作者")
        try expect(video.metrics.likes == "0" && video.metrics.collects == "347" && video.metrics.comments == "168", "互动栏定位、真实零值与正文数值隔离")
        try expect(video.shareButton?.display == 3, "视频分享控件属于正确显示器")
        let deleted = try Page.read("""
        <?xml version="1.0"?><hierarchy><window display="3"><node package="com.xingin.xhs" bounds="[0,0][2560,1600]">
        <node package="com.xingin.xhs" text="当前内容无法展示" bounds="[900,700][1700,800]"/>
        <node package="com.xingin.xhs" text="跳转Ta的主页 · 3秒" bounds="[900,810][1700,900]"/>
        </node></window></hierarchy>
        """)
        try expect(deleted.deletedHint == "当前内容无法展示" && !deleted.isNote, "按用户口径记录失效提示，不能等待跳转主页才判断")
        let comment = try Page.read("""
        <?xml version="1.0"?><hierarchy><node package="com.xingin.xhs" bounds="[0,0][1000,1000]">
        <node package="com.xingin.xhs" text="作者说当前内容无法展示怎么办" bounds="[1,100][800,150]"/>
        </node></hierarchy>
        """)
        try expect(comment.deletedHint == nil, "正文和评论提到删除不能当作系统删除提示")
        let guest = try Page.read("""
        <?xml version="1.0"?><hierarchy><window display="2"><node package="com.xingin.xhs" bounds="[0,0][1600,2560]">
        <node package="com.xingin.xhs" content-desc="图片,第1张,共6张,双指左划或右划即可查看更多内容" bounds="[280,225][1320,1611]"/>
        <node package="com.xingin.xhs" text="登录查看更多精彩内容" bounds="[134,2335][1382,2386]"/>
        <node package="com.xingin.xhs" text="去登录" bounds="[1423,2335][1528,2386]"/>
        <node package="com.xingin.xhs" text="说点什么..." content-desc="评论框" bounds="[38,2442][1039,2534]"/>
        <node package="com.xingin.xhs" content-desc="收藏 0" bounds="[1241,2438][1391,2539]"/>
        </node></window></hierarchy>
        """)
        try expect(guest.isReadableNote && !guest.isNote && guest.restriction == nil,
                   "未登录笔记的媒体与工具栏可判定可访问，不要求采集作者，也不把去登录横条误判为限制")
        let login = try Page.read("""
        <?xml version="1.0"?><hierarchy><node package="com.xingin.xhs" bounds="[0,0][1600,2560]">
        <node package="com.xingin.xhs" text="请先登录" bounds="[100,200][1000,300]"/>
        </node></hierarchy>
        """)
        try expect(!login.isReadableNote && login.deletedHint == nil && login.restriction == "请先登录",
                   "登录拦截既不能算可访问，也不能误判已删除")
        let stopped = StopToken(); stopped.stop()
        do { try stopped.check(); throw ToolkitError.message("停止必须生效") } catch ToolkitError.stopped { }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xhs-toolkit-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try XLSXWriter.makeOutputURL(in: directory)
        var row = NoteResult(original: "=HYPERLINK(\"bad\")", noteID: id)
        row.author = "作者<&>"; row.likes = "0"; row.shareURL = url
        try XLSXWriter.write(rows: [row], to: output)
        let xml = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", output.path, "xl/worksheets/sheet1.xml"])
        try expect(xml.contains("作者&lt;&amp;&gt;") && xml.contains("=HYPERLINK") && !xml.contains("<f>"), "Excel 字符转义与公式注入防护")
        try expect(xml.contains("A1:M2") && xml.contains("安卓分享原链"), "Excel 列与独立分享原链字段")
        let second = try XLSXWriter.makeOutputURL(in: directory)
        try expect(second != output, "同秒导出不得覆盖已有报告")
        print("Links, Android display, video toolbar, deleted state, stop and Excel checks passed")
    }
}
