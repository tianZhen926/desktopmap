import AppKit
import SwiftUI

final class DesktopPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 桌面层的窗口默认不算「激活点击」，不放开首击的话第一次点只激活 App、按钮不响应。
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    let window: DesktopPanel
    private let store: Store
    private let hosting: PanelHostingView<ContentView>
    /// 必须用图标层：.desktopWindow 在 Finder 壁纸/图标窗口之下，那层会吃掉所有点击。
    private let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    private var screenToken: Any?

    init(store: Store) {
        self.store = store
        self.hosting = PanelHostingView(rootView: ContentView(store: store))
        self.window = DesktopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 384, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        super.init()

        window.title = "桌面地图"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(width: 340, height: 380)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.delegate = self
        window.contentView = hosting
        window.setFrameAutosaveName("DesktopMap.frame")
        applyPin()
        placeOnChosenScreen(firstLaunch: true)

        for name: Notification.Name in [.dmRaise, .dmLower, .dmTogglePin, .dmRevealList, .dmPlace] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(handle(_:)), name: name, object: nil)
        }
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // 拔屏/加屏后系统会把窗口留在原地，这里重新按设置归位。
            self?.placeOnChosenScreen(firstLaunch: false)
            self?.store.touch()
        }
    }

    deinit {
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    @objc private func handle(_ note: Notification) {
        switch note.name {
        case .dmRaise:
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
        case .dmLower:
            applyPin()
        case .dmTogglePin:
            store.setPin(desktop: !store.pinIsDesktop)
            applyPin()
        case .dmRevealList:
            NSWorkspace.shared.activateFileViewerSelecting([store.listURL])
        case .dmPlace:
            placeOnChosenScreen(firstLaunch: false)
        default:
            break
        }
    }

    private func applyPin() {
        window.level = store.pinIsDesktop ? desktopLevel : .floating
    }

    private func placeOnChosenScreen(firstLaunch: Bool) {
        let chosen = ScreenCatalog.screen(forID: store.screenID)
        let onSomeScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
        var target: NSScreen?
        if let chosen, firstLaunch || !chosen.frame.intersects(window.frame) {
            target = chosen
        } else if chosen == nil, firstLaunch || !onSomeScreen {
            target = ScreenCatalog.primary ?? NSScreen.screens.first
        }
        guard let screen = target else { return }
        let visible = screen.visibleFrame
        let size = firstLaunch
            ? NSSize(width: 384, height: min(560, visible.height - 32))
            : window.frame.size
        let origin = NSPoint(x: visible.maxX - size.width - 18, y: visible.maxY - size.height - 18)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        DMLog.line("面板定位 选择=\(store.screenID.isEmpty ? "自动" : store.screenID) 屏=\(Int(screen.frame.width))×\(Int(screen.frame.height))")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var probeMode = false
    let store = Store.shared
    var controller: PanelController!
    var console: ConsoleController!
    var recorder: ClickRecorder!
    var cards: CardOverlayController!
    var status: StatusBarController!
    var hotKey: GlobalHotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DMLog.line("启动")
        store.load()
        controller = PanelController(store: store)
        console = ConsoleController(store: store)
        recorder = ClickRecorder()
        cards = CardOverlayController(store: store)
        status = StatusBarController(store: store, panel: controller, console: console, cards: cards)
        hotKey = GlobalHotKey.toggleCards {
            NotificationCenter.default.post(name: .dmToggleCards, object: nil)
        }
        controller.show()
        buildMenu()
        store.startTimers()
        NotificationCenter.default.addObserver(
            self, selector: #selector(openConsole), name: .dmConsole, object: nil)
        probeIfNeeded()
    }

    /// 自检：用辅助功能接口按下面板的按钮，看动作链路通不通。
    private func probeIfNeeded() {
        guard AppDelegate.probeMode else { return }
        Probe.run(store: store, console: console, panel: controller, status: status,
                  cards: cards, hotKey: hotKey)
    }

    @objc private func openConsole() {
        DMLog.line("打开控制台")
        console.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.reloadVolume()
        store.touch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于桌面地图",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let refresh = NSMenuItem(title: "重新测量", action: #selector(postRefresh), keyEquivalent: "r")
        refresh.target = self
        appMenu.addItem(refresh)
        let add = NSMenuItem(title: "添加条目", action: #selector(postAdd), keyEquivalent: "n")
        add.target = self
        appMenu.addItem(add)
        let console = NSMenuItem(title: "控制台…", action: #selector(openConsole), keyEquivalent: ",")
        console.target = self
        appMenu.addItem(console)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏桌面地图",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出桌面地图",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        let fields: [(String, Selector, String)] = [
            ("撤销", Selector(("undo:")), "z"),
            ("重做", Selector(("redo:")), "Z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("拷贝", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, sel, key) in fields {
            editMenu.addItem(NSMenuItem(title: title, action: sel, keyEquivalent: key))
        }

        NSApp.mainMenu = mainMenu
    }

    @objc private func postRefresh() { NotificationCenter.default.post(name: .dmRefresh, object: nil) }
    @objc private func postAdd() { NotificationCenter.default.post(name: .dmAdd, object: nil) }
}

enum DumpCLI {
    static func run() {
        let store = Store.shared
        store.load()
        for section in store.groups {
            print("[\(section.name)]  合计 \(ByteFormat.string(store.bytes(of: section.items)))")
            for entry in section.items {
                let size = store.statSync(entry.path).display
                print("  \(entry.risk.chip) \(size)  \(entry.label)  ->  \(entry.path)")
            }
        }
        print("\(store.volumeSummary)，共 \(store.entries.count) 条")
    }
}

if CommandLine.arguments.contains("--dump") {
    DumpCLI.run()
    exit(0)
}

AppDelegate.probeMode = CommandLine.arguments.contains("--probe")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
