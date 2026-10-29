import Foundation

enum NotePacingTests {
    static func run() throws {
        var events = [String]()
        try NotePacing.afterReadableNote(pause: { events.append("wait\(Int($0))") },
                                         returnHome: { events.append("home") })
        try SelfTests.expect(events == ["wait3", "home", "wait2"], "正常笔记先在页内停留3秒，再回首页等待2秒")

        events = []
        try NotePacing.afterDeletedNote(waitForAuthor: { events.append("author-ready") },
                                        returnHome: { events.append("home") },
                                        pause: { events.append("wait\(Int($0))") })
        try SelfTests.expect(events == ["author-ready", "home", "wait2"], "失效笔记必须等自动跳转完成后才返回首页")

        events = []
        do {
            try NotePacing.afterReadableNote(pause: { _ in throw ToolkitError.stopped },
                                             returnHome: { events.append("home") })
            throw ToolkitError.message("停留时暂停未生效")
        } catch ToolkitError.stopped { }
        try SelfTests.expect(events.isEmpty, "笔记内暂停不能继续返回首页")

        do {
            try NotePacing.afterDeletedNote(waitForAuthor: { throw ToolkitError.stopped },
                                            returnHome: { events.append("home") },
                                            pause: { events.append("wait\(Int($0))") })
            throw ToolkitError.message("跳转时暂停未生效")
        } catch ToolkitError.stopped { }
        try SelfTests.expect(events.isEmpty, "自动跳转未完成时不能提前返回或开始下一条")

        do {
            try NotePacing.afterReadableNote(pause: { events.append("wait\(Int($0))") },
                                             returnHome: { throw ToolkitError.stopped })
            throw ToolkitError.message("返回失败后仍继续")
        } catch ToolkitError.stopped { }
        try SelfTests.expect(events == ["wait3"], "返回首页失败时停止流程，不能继续下一条")

        func page(_ labels: [String]) throws -> Page {
            let nodes = labels.map { "<node package=\"com.xingin.xhs\" text=\"\($0)\" bounds=\"[100,100][400,150]\"/>" }.joined()
            return try Page.read("<?xml version=\"1.0\"?><hierarchy><node package=\"com.xingin.xhs\" bounds=\"[0,0][1600,2560]\">\(nodes)</node></hierarchy>")
        }
        let profile = try page(["粉丝", "关注", "获赞与收藏", "笔记"])
        let redirecting = try page(["当前内容无法展示", "跳转Ta的主页 · 3秒", "粉丝", "关注", "笔记"])
        let login = try page(["手机号登录", "帮助"])
        try SelfTests.expect(profile.isAuthorProfile && !profile.isHome, "识别自动跳转后的作者主页")
        try SelfTests.expect(!redirecting.isAuthorProfile, "失效提示仍在显示时不能视为跳转完成")
        try SelfTests.expect(login.isLoginPage && !login.isAuthorProfile && login.deletedHint == nil,
                             "登录页不能当作作者主页或新的失效笔记")
        let readable = try Page.read("""
        <?xml version="1.0"?><hierarchy><node package="com.xingin.xhs" bounds="[0,0][1600,2560]">
        <node package="com.xingin.xhs" content-desc="图片,第1张,共1张" bounds="[280,225][1320,1611]"/>
        <node package="com.xingin.xhs" text="说点什么..." content-desc="评论框" bounds="[38,2442][1166,2534]"/>
        <node package="com.xingin.xhs" content-desc="收藏 1" bounds="[1320,2438][1421,2539]"/>
        </node></hierarchy>
        """)
        let blank = try page([]), panel = try page(["分享至", "复制链接"])
        var frames = [blank, panel, panel, blank, readable]
        var backs = 0
        try NotePacing.confirmNoteAfterShare(readPage: { frames.removeFirst() },
                                             dismissShare: { backs += 1 }, pause: { _ in })
        try SelfTests.expect(frames.isEmpty && backs == 1,
                             "分享关闭时短暂空帧不应停批，旧分享控件残留时也只返回一次")
        frames = [blank, blank, readable]; backs = 0
        try NotePacing.confirmNoteAfterShare(readPage: { frames.removeFirst() },
                                             dismissShare: { backs += 1 }, pause: { _ in })
        try SelfTests.expect(backs == 0, "分享已经收起时只等待画面恢复，不能误按返回退出笔记")
        do {
            try NotePacing.confirmNoteAfterShare(readPage: { panel }, dismissShare: { backs += 1 }, pause: { _ in })
            throw ToolkitError.message("分享面板一直不消失却被放行")
        } catch ToolkitError.message(let reason) {
            try SelfTests.expect(reason.contains("等待页面稳定"), "无法确认笔记时仍需明确停止")
        }
        try SelfTests.expect(backs == 1, "等待超时也不能连续返回")
        do {
            try NotePacing.confirmNoteAfterShare(readPage: { login }, dismissShare: { backs += 1 }, pause: { _ in })
            throw ToolkitError.message("登录页被当作笔记页放行")
        } catch ToolkitError.message(let reason) {
            try SelfTests.expect(reason.contains("登录、访问限制"), "真实登录拦截继续停止，不作为动画跳过")
        }
        try SelfTests.expect(backs == 1, "遇到登录页不能操作返回或登录")
        print("Note dwell, home wait, redirect order, share transition and cancellation checks passed")
    }
}
