import AppKit

/// 自检：确认两个窗口都在、层级对、控件数量对。
/// 注意：不要用 NSView.hitTest 判断 SwiftUI 控件能不能点——SwiftUI 的鼠标事件
/// 走 hosting view 自己的手势系统，控件视图的 hitTest 命中的是容器，这是正常的。
enum Probe {
    static func run(store: Store, console: ConsoleController, panel: PanelController,
                    status: StatusBarController, cards: CardOverlayController, hotKey: GlobalHotKey) {
        console.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dump(store: store, panel: panel, console: console, status: status, cards: cards, hotKey: hotKey)
            cards.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                var controls = 0
                var views = 0
                if let root = cards.probeWindow?.contentView {
                    collect(root, count: &controls, views: &views)
                }
                print("卡片浮层 已显示=\(cards.isVisible) 控件=\(controls) 视图=\(views) "
                    + "位置=\(cards.probeWindow.map { NSStringFromRect($0.frame) } ?? "无")")
                exit(0)
            }
        }
    }

    private static func dump(store: Store, panel: PanelController, console: ConsoleController,
                             status: StatusBarController, cards: CardOverlayController,
                             hotKey: GlobalHotKey) {
        print("后台排队任务=\(store.pendingWork) 条目=\(store.entries.count) 已测量=\(store.info.count)")
        print("快捷键 已注册=\(hotKey.isRegistered) \(GlobalHotKey.display) 备份=\(store.backupCount) 份"
            + " 最新=\(store.latestBackup?.lastPathComponent ?? "无") 剩余=\(store.freeShort)")
        for screen in ScreenCatalog.all {
            print("屏幕 \(screen.title) id=\(screen.id)")
        }
        print("面板选择=\(store.screenID.isEmpty ? "自动" : store.screenID) 面板位置=\(NSStringFromRect(panel.window.frame))")
        print("状态栏菜单条目=\(status.forceBuildForProbe())")
        print("卡片浮层 模式=\(store.cardMode) \(cards.probeSummary()) 分组=\(store.cardGroups.count) 条目=\(store.entries.count)")
        let windows: [(String, NSWindow?)] = [("面板", panel.window), ("控制台", console.window)]
        for (name, maybeWindow) in windows {
            guard let window = maybeWindow else { continue }
            var controls = 0
            var views = 0
            if let root = window.contentView { collect(root, count: &controls, views: &views) }
            print("\(name) «\(window.title)» 层级=\(window.level.rawValue) 可见=\(window.isVisible) "
                + "key=\(window.isKeyWindow) 控件=\(controls)/视图=\(views) 首击=\(window.contentView?.acceptsFirstMouse(for: nil) ?? false)")
        }
    }

    private static func collect(_ view: NSView, count: inout Int, views: inout Int) {
        views += 1
        if view is NSControl { count += 1 }
        for child in view.subviews { collect(child, count: &count, views: &views) }
    }
}
