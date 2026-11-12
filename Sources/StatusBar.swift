import AppKit

/// 顶部状态栏入口。面板贴在桌面层，平时看不见摸不着，
/// 所以给一个常驻菜单：显隐面板、开控制台、按分组跳、直接打开常用缓存目录。
final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: Store
    private let panel: PanelController
    private let console: ConsoleController
    private let cards: CardOverlayController
    private let item: NSStatusItem
    private let menu = NSMenu()

    init(store: Store, panel: PanelController, console: ConsoleController, cards: CardOverlayController) {
        self.store = store
        self.panel = panel
        self.console = console
        self.cards = cards
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let image = NSImage(systemSymbolName: "map", accessibilityDescription: "桌面地图")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "桌面地图"
        applyVolumeTitle()

        menu.delegate = self
        // 卡片模式下不能挂着 menu：NSStatusItem 一旦有 menu，按钮的 action 就永远收不到点击。
        applyClickBehavior()
        for name: Notification.Name in [.dmCardMode, .dmVolume] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(notificationArrived(_:)), name: name, object: nil)
        }
    }

    @objc private func notificationArrived(_ note: Notification) {
        if note.name == .dmVolume {
            applyVolumeTitle()
        } else {
            applyClickBehavior()
        }
    }

    /// 图标旁边挂一个剩余空间，不用点开就能看到磁盘还剩多少；低于 30G 标红。
    private func applyVolumeTitle() {
        guard let button = item.button else { return }
        let text = store.freeShort
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .foregroundColor: store.freeSpaceIsLow ? NSColor.systemRed : NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        ])
    }

    private func applyClickBehavior() {
        if store.cardMode {
            item.menu = nil
            item.button?.target = self
            item.button?.action = #selector(statusClicked)
            item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        } else {
            item.button?.target = nil
            item.button?.action = nil
            item.menu = menu
        }
    }

    /// 卡片模式下左键开合浮层，右键仍然要能出菜单——
    /// 不然「控制台 / 改为贴在桌面 / 退出」这些出口在卡片模式里就全没了。
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseDown {
            popUpMenu()
        } else {
            toggleCards()
        }
    }

    private func popUpMenu() {
        DMLog.line("状态栏 右键出菜单")
        guard let button = item.button else { return }
        menuNeedsUpdate(menu)
        // 不挂 item.menu（挂了左键就废了），直接手动弹。
        // 按钮坐标系是不是 flipped 各版本不一样，两种都算一下，菜单才会贴在图标下面而不是头顶。
        let y: CGFloat = button.isFlipped ? button.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
    }

    var menuItemCount: Int { menu.numberOfItems }

    /// 自检用：菜单只在展开时才填内容，这里手动跑一遍构建看有没有异常。
    func forceBuildForProbe() -> Int {
        menuNeedsUpdate(menu)
        return menu.numberOfItems
    }

    func menuNeedsUpdate(_ n: NSMenu) { rebuild(n) }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = "\(store.volumeSummary) · 可回收 \(ByteFormat.string(store.deletableBytes)) · \(store.entries.count) 条"
        menu.addItem(disabled(store.isMeasuring ? "正在测量…" : header))
        menu.addItem(.separator())

        // 状态栏菜单不抢快捷键：⌘R/⌘,/⌘Q 已经挂在程序主菜单上，重复定义会互相顶掉。
        add(menu, panel.window.isVisible ? "隐藏桌面面板" : "显示桌面面板", #selector(togglePanel), key: "")
        add(menu, "控制台…", #selector(openConsole), key: "")
        add(menu, "重新测量", #selector(measure), key: "")
        add(menu, store.cardMode ? "关闭卡片模式（回到菜单）" : "开启卡片模式（启动台样式）",
            #selector(toggleCardMode), key: "")
        if !store.cardMode {
            add(menu, "展开卡片浮层一次", #selector(showCards), key: "")
        }
        add(menu, "开合卡片浮层 全局键 \(GlobalHotKey.display)", #selector(toggleCards), key: "")
        menu.addItem(.separator())

        let groups = NSMenu()
        for name in store.groupNames {
            let count = store.groups.first { $0.name == name }?.items.count ?? 0
            let entry = NSMenuItem(title: "\(name)（\(count)）",
                                   action: #selector(revealGroup), keyEquivalent: "")
            entry.target = self
            entry.representedObject = name
            groups.addItem(entry)
        }
        if groups.numberOfItems == 0 {
            groups.addItem(disabled("清单是空的"))
        }
        let groupItem = NSMenuItem(title: "跳到分组", action: nil, keyEquivalent: "")
        groupItem.submenu = groups
        menu.addItem(groupItem)

        let caches = NSMenu()
        let safe = store.entries.filter { $0.risk == .safe }
            .sorted { (store.info[$0.path]?.bytes ?? 0) > (store.info[$1.path]?.bytes ?? 0) }
        for entry in safe.prefix(8) {
            let size = store.info[entry.path]?.display ?? "…"
            let item = NSMenuItem(title: "\(size)  \(entry.label)",
                                  action: #selector(openPath), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.path
            caches.addItem(item)
        }
        if caches.numberOfItems == 0 {
            caches.addItem(disabled("还没有标为「可删」的条目"))
        }
        let cacheItem = NSMenuItem(title: "常用缓存", action: nil, keyEquivalent: "")
        cacheItem.submenu = caches
        menu.addItem(cacheItem)
        menu.addItem(.separator())

        add(menu, store.pinIsDesktop ? "改为悬浮置顶" : "改为贴在桌面", #selector(togglePin), key: "")
        add(menu, LoginItemHelper.isEnabled ? "关闭开机自启" : "设为开机自启", #selector(toggleLogin), key: "")
        menu.addItem(.separator())
        add(menu, "退出桌面地图", #selector(quit), key: "")
    }

    // MARK: - builders

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    // MARK: - actions

    @objc private func togglePanel() {
        DMLog.line("菜单 显隐面板")
        panel.window.isVisible ? panel.hide() : panel.show()
    }

    @objc private func openConsole() {
        DMLog.line("菜单 控制台")
        console.show()
    }

    @objc private func toggleCards() {
        DMLog.line("状态栏 点图标（卡片模式）")
        cards.toggle()
    }

    @objc private func toggleCardMode() {
        store.cardMode = !store.cardMode
        DMLog.line("状态栏 卡片模式 → \(store.cardMode ? "开" : "关")")
    }

    @objc private func showCards() {
        DMLog.line("状态栏 展开卡片一次")
        cards.show()
    }

    @objc private func measure() {
        DMLog.line("菜单 重新测量")
        store.measureAll()
    }

    @objc private func revealGroup(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        DMLog.line("菜单 跳到分组 \(name)")
        store.revealGroup(name)
    }

    @objc private func openPath(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let full = path.expanded
        guard FileManager.default.fileExists(atPath: full) else {
            store.say("路径当前不存在：\(path)")
            DMLog.line("菜单 打开失败（不存在）\(path)")
            return
        }
        DMLog.line("菜单 打开 \(path)")
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: full)])
    }

    @objc private func togglePin() {
        DMLog.line("菜单 切换层级")
        NotificationCenter.default.post(name: .dmTogglePin, object: nil)
    }

    @objc private func toggleLogin() {
        if LoginItemHelper.isEnabled { LoginItemHelper.disable() } else { LoginItemHelper.enable() }
        DMLog.line("菜单 开机自启 → \(LoginItemHelper.isEnabled ? "已开" : "已关")")
        store.touch()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
