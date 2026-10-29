import Foundation

enum NotePacing {
    static func confirmNoteAfterShare(readPage: () throws -> Page,
                                      dismissShare: () throws -> Void,
                                      pause: (TimeInterval) throws -> Void) throws {
        var dismissed = false
        for _ in 0..<15 {
            let current = try readPage()
            if current.find(exact: ["分享至", "分享到"]) != nil {
                // The panel's old controls can remain visible during its closing animation.
                // Send Back once, then only observe until the note is readable again.
                if !dismissed { try dismissShare(); dismissed = true }
            } else if current.isReadableNote { return }
            else if current.isLoginPage || current.restriction != nil || current.deletedHint != nil {
                throw ToolkitError.message("分享复制后客户端出现登录、访问限制或内容失效提示，已停止批次，保留已取得的结果。")
            }
            try pause(0.2)
        }
        throw ToolkitError.message("取得分享结果后，等待页面稳定仍未确认回到笔记页，已停止批次，保留已取得的结果。")
    }

    static func afterReadableNote(pause: (TimeInterval) throws -> Void,
                                  returnHome: () throws -> Void) throws {
        try pause(3)
        try returnHome()
        try pause(2)
    }

    static func afterDeletedNote(waitForAuthor: () throws -> Void,
                                 returnHome: () throws -> Void,
                                 pause: (TimeInterval) throws -> Void) throws {
        try waitForAuthor()
        try returnHome()
        try pause(2)
    }
}
