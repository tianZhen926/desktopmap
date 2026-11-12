import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 无边框全屏窗需要 key 才能收 Esc，默认 borderless 窗口做不到。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 启动台样式的卡片浮层：状态栏图标点击后铺满主屏，模糊背景 + 分组卡片网格，
/// 点卡片 = 在访达里选中该目录然后关掉。仍然只跳转、不删除。
final class CardOverlayController {
    private let store: Store
    private var window: OverlayWindow?
    private var keyMonitor: Any?

    init(store: Store) {
        self.store = store
        for name: Notification.Name in [.dmHideCards, .dmCardMode, .dmToggleCards] {
            NotificationCenter.default.addObserver(self, selector: #selector(handle(_:)), name: name, object: nil)
        }
    }

    @objc private func handle(_ note: Notification) {
        if note.name == .dmToggleCards {
            DMLog.line("快捷键 触发 当前已显示=\(isVisible)")
            toggle()
            return
        }
        // 关掉卡片模式时浮层得跟着收，否则会一直压在屏幕上关不掉。
        if note.name == .dmCardMode, store.cardMode { return }
        hide()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// 自检用
    var probeWindow: NSWindow? { window }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// 浮层铺哪块屏：控制台里指定过就听它的，没指定就跟着鼠标指针那块——
    /// 在 2 号屏干活时不用回头去够状态栏图标。
    private var targetScreen: NSScreen? {
        if let chosen = ScreenCatalog.screen(forID: store.screenID) { return chosen }
        let point = NSEvent.mouseLocation
        if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return underMouse
        }
        return ScreenCatalog.primary ?? NSScreen.main
    }

    func show() {
        guard let screen = targetScreen else { return }
        if window == nil { build() }
        guard let window else { return }
        window.setFrame(screen.frame, display: true)
        store.cardFilter = ""
        store.status = ""
        store.cardDetail = nil
        store.cardDropTarget = nil
        store.cardsRevealed = false
        store.measureAll(refreshKnown: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 卡片先停在「没露出」的状态，下一拍再翻真：同一拍里赋值没有起止两个值，动画不会跑。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.cardsRevealed = true
            self.store.touch()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // 53 = Esc：启动台的退出键
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            return event
        }
        DMLog.line("卡片 打开 屏=\(Int(screen.frame.width))×\(Int(screen.frame.height))")
    }

    func hide() {
        removeKeyMonitor()
        guard let window, window.isVisible, !isClosing else { return }
        isClosing = true
        store.cardsRevealed = false
        store.touch()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            window.orderOut(nil)
            window.alphaValue = 1
            self.isClosing = false
        })
    }

    private var isClosing = false

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// 自检用：确认窗口能建出来、层级够高压过普通窗口。
    func probeSummary() -> String {
        if window == nil { build() }
        guard let window else { return "建不出来" }
        return "层级=\(window.level.rawValue) 全屏=\(window.styleMask.contains(.borderless)) 可key=\(window.canBecomeKey)"
    }

    private func build() {
        let overlay = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.animationBehavior = .none
        overlay.isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        let host = PanelHostingView(rootView: CardGridView(
            store: store,
            choose: { [weak self] entry in self?.pick(entry) },
            addFolder: { [weak self] group in self?.addFolders(to: group) },
            remove: { [weak self] entry in self?.drop(entry) },
            edit: { [weak self] entry in self?.edit(entry) },
            receiveDrop: { [weak self] providers, group in self?.receiveDrop(providers, into: group) }))
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        overlay.contentView = effect
        window = overlay
    }

    private func pick(_ entry: Entry) {
        DMLog.line("卡片 选 \(entry.path)")
        store.open(entry)
        hide()
    }

    /// 撤卡片：只动清单，磁盘上的文件一个字都不碰。
    private func drop(_ entry: Entry) {
        DMLog.line("卡片 撤卡片 \(entry.path)")
        withAnimation(.easeOut(duration: 0.16)) {
            store.removeWithUndo(entry)
        }
    }

    /// 编辑统一交给控制台：浮层里内嵌 EditorSheet 的话，它的「选路径」
    /// 会开出层级只有 8 的选择器，被 102 层的浮层压在后面。
    private func edit(_ entry: Entry) {
        DMLog.line("卡片 去控制台编辑 \(entry.path)")
        hide()
        NotificationCenter.default.post(name: .dmEditEntry, object: entry)
    }

    // MARK: - 拖进来的目录

    private var dropBuffer: [(url: URL, group: String)] = []
    private var dropScheduled = false

    /// loadObject 的回调不保证在主线程，所以先逐条收进缓冲，下一拍按分组一次性提交：
    /// 一次拖 5 个目录只出一条提示，也不会多线程同写一个数组。
    private func receiveDrop(_ providers: [NSItemProvider], into group: String) {
        DMLog.line("卡片 拖入 \(providers.count) 项 → \(group)")
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let self, let url, isDirectoryPath(url.path) else { return }
                DispatchQueue.main.async { self.bufferDrop(url, group: group) }
            }
        }
    }

    private func bufferDrop(_ url: URL, group: String) {
        dropBuffer.append((url, group))
        guard !dropScheduled else { return }
        dropScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dropScheduled = false
            let batch = self.dropBuffer
            self.dropBuffer.removeAll()
            var byGroup: [(group: String, urls: [URL])] = []
            for item in batch {
                if let i = byGroup.firstIndex(where: { $0.group == item.group }) {
                    byGroup[i].urls.append(item.url)
                } else {
                    byGroup.append((item.group, [item.url]))
                }
            }
            for section in byGroup {
                self.store.addFolders(section.urls, group: section.group)
            }
        }
    }

    /// 添加文件夹：先把浮层收掉再开选择器。
    /// 选择器是普通模态面板（层级 8），浮层在 102 会把它整个盖住，看不见也点不到；
    /// 收掉再弹、选完再展开，比把选择器硬抬到浮层上面稳。
    private func addFolders(to group: String) {
        let keepFilter = store.cardFilter
        DMLog.line("卡片 添加文件夹 分组=\(group)")
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            let urls = FilePicker.folders(startingAt: "~/")
            DMLog.line("卡片 选择器 返回 \(urls.count) 个目录")
            if !urls.isEmpty {
                self.store.addFolders(urls, group: group)
            }
            // show() 会清掉提示，这里留一份贴回去，不然「已加入 N 条」看不到。
            let toast = self.store.status
            self.show()
            self.store.cardFilter = keepFilter
            self.store.status = toast
            self.store.touch()
        }
    }
}

// MARK: - grid

struct CardGridView: View {
    @ObservedObject var store: Store
    let choose: (Entry) -> Void
    let addFolder: (String) -> Void
    let remove: (Entry) -> Void
    let edit: (Entry) -> Void
    let receiveDrop: ([NSItemProvider], String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ZStack {
            // 空白处点一下就收起来，和启动台点桌面退出一样
            Color.clear.contentShape(Rectangle()).onTapGesture { close() }

            VStack(spacing: 12) {
                header
                hint

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(store.cardGroups.enumerated()), id: \.element.name) { pair in
                            section(pair.element, order: pair.offset)
                        }
                        if store.cardGroups.isEmpty {
                            Text(emptyReason)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(26)

            if let entry = store.cardDetail {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    CardDetailView(entry: entry, store: store,
                                   edit: { edit(entry) },
                                   close: { inspect(nil) })
                        .padding(.trailing, 26)
                        .padding(.vertical, 60)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - pieces

    private var header: some View {
        HStack(spacing: 8) {
            Text("桌面地图").font(.system(size: 15, weight: .bold))
            TextField("搜索名称 / 路径 / 备注", text: store.binding({ store.cardFilter }, {
                store.cardFilter = $0
                store.touch()
            }))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
            Button("添加文件夹") { addFolder(store.consoleGroup) }
                .help("选中的目录各加一条到「\(store.consoleGroup)」；想加进别的分组，点分组名右边的 ＋，或者直接从访达拖")
            HStack(spacing: 3) {
                Text("归到").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("分组名", text: store.binding({ store.consoleGroup }, {
                    store.consoleGroup = $0
                    store.touch()
                }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .font(.system(size: 11))
            }
            .help("顶栏「添加文件夹」加进来的都落在这个分组；打个没见过的名字就是新建一个类别。想加到别的组，点那个组标题右边的 ＋，或者把文件夹直接拖到那个组上")
            Toggle("只看可删", isOn: store.binding({ store.cardOnlySafe }, { store.cardOnlySafe = $0 }))
                .toggleStyle(.button)
                .controlSize(.small)
            Toggle("只看 1G 以上", isOn: store.binding({ store.cardOnlyBig }, { store.cardOnlyBig = $0 }))
                .toggleStyle(.button)
                .controlSize(.small)
            Spacer()
            Text(store.status.isEmpty ? store.volumeSummary : store.status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if store.canUndoRemove {
                Button("放回清单") {
                    DMLog.line("卡片 放回清单")
                    withAnimation(.easeOut(duration: 0.18)) { store.undoRemove() }
                }
                .help("把刚才撤掉的那张卡片贴回去")
            }
            Button("退出卡片模式") { store.cardMode = false }
            Button("关闭") { close() }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(store.cardsRevealed ? 1 : 0)
        .offset(y: store.cardsRevealed ? 0 : -10)
        .animation(reveal(0), value: store.cardsRevealed)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Text("点卡片 = 在访达里选中；ⓘ = 看详情；✕ = 撤掉这张卡片（不删文件）。也可以从访达把文件夹直接拖到某个分组上。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func section(_ section: (name: String, items: [Entry]), order: Int) -> some View {
        let isTarget = store.cardDropTarget == section.name
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(section.name).font(.system(size: 13, weight: .semibold))
                Text("\(section.items.count) 条 · \(ByteFormat.string(store.bytes(of: section.items)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button { addFolder(section.name) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("往「\(section.name)」添加文件夹")
                if isTarget {
                    Text("松手就加到这里")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .opacity(store.cardsRevealed ? 1 : 0)
            .offset(y: store.cardsRevealed ? 0 : 8)
            .animation(reveal(order * 3), value: store.cardsRevealed)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { item in
                    CardCell(entry: item.element,
                             order: order * 3 + item.offset,
                             store: store,
                             choose: { choose(item.element) },
                             remove: { remove(item.element) },
                             inspect: { inspect(item.element) })
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isTarget ? Color.accentColor : Color.clear, lineWidth: 2))
        .onDrop(of: [UTType.fileURL], isTargeted: dropTargetBinding(section.name)) { providers in
            receiveDrop(providers, section.name)
            return true
        }
        .transition(.opacity)
    }

    private func inspect(_ entry: Entry?) {
        withAnimation(.easeOut(duration: 0.18)) {
            store.cardDetail = (store.cardDetail == entry && entry != nil) ? nil : entry
        }
    }

    private func dropTargetBinding(_ name: String) -> Binding<Bool> {
        store.binding({ store.cardDropTarget == name }, { hovering in
            if hovering {
                store.cardDropTarget = name
            } else if store.cardDropTarget == name {
                store.cardDropTarget = nil
            }
        })
    }

    private var emptyReason: String {
        if !store.entries.isEmpty, store.cardGroups.isEmpty {
            return "当前筛选（\(store.cardOnlySafe ? "只看可删" : "")\(store.cardOnlyBig ? " 只看1G以上" : "")「\(store.cardFilter)」）下没有条目"
        }
        return store.entries.isEmpty ? "清单是空的" : "没有匹配「\(store.cardFilter)」的条目"
    }

    private func close() {
        NotificationCenter.default.post(name: .dmHideCards, object: nil)
    }

    /// 入场按序号错开，退场不排队一次性收——启动台就是这个手感。
    private func reveal(_ order: Int) -> Animation {
        cardReveal(revealed: store.cardsRevealed, order: order)
    }
}

private func cardReveal(revealed: Bool, order: Int) -> Animation {
    revealed
        ? .spring(response: 0.3, dampingFraction: 0.72).delay(min(Double(order) * 0.018, 0.34))
        : .easeOut(duration: 0.12)
}

private struct CardCell: View {
    let entry: Entry
    let order: Int
    @ObservedObject var store: Store
    let choose: () -> Void
    let remove: () -> Void
    let inspect: () -> Void

    private var detail: PathInfo? { store.info[entry.path] }

    var body: some View {
        // 角上的两个按钮必须是这层的兄弟按钮：套进卡片按钮的 label 里就点不到了。
        ZStack(alignment: .topLeading) {
            Button(action: choose) { card }
                .buttonStyle(.plain)
                .help(entry.path)
            HStack(spacing: 3) {
                Button(action: inspect) {
                    Image(systemName: store.cardDetail?.id == entry.id ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 13))
                }
                .help("看这条的完整路径和备注")
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .help("撤掉这张卡片（只从清单移除，不删文件）")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(5)
        }
        .opacity(store.cardsRevealed ? 1 : 0)
        .scaleEffect(store.cardsRevealed ? 1 : 0.7)
        .offset(y: store.cardsRevealed ? 0 : 12)
        .animation(cardReveal(revealed: store.cardsRevealed, order: order), value: store.cardsRevealed)
    }

    private var card: some View {
        VStack(spacing: 5) {
            Image(nsImage: store.icon(for: entry.path))
                .resizable()
                .frame(width: 58, height: 58)
            Text(entry.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Text(detail?.display ?? "…")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(detail?.exists == false ? Color.red : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(store.cardDetail?.id == entry.id ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(riskColor)
                .frame(width: 7, height: 7)
                .padding(7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var riskColor: Color {
        switch entry.risk {
        case .safe: return .green
        case .caution: return .orange
        case .keep: return .gray
        }
    }
}

/// 右侧详情条。只读 + 跳转类动作；编辑要回控制台，因为浮层层级太高，
/// EditorSheet 里的路径选择器会被压在浮层后面。
private struct CardDetailView: View {
    let entry: Entry
    @ObservedObject var store: Store
    let edit: () -> Void
    let close: () -> Void

    private var detail: PathInfo? { store.info[entry.path] }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            row("分组", entry.group)
            row("标记", entry.risk.chip)
            row("大小", detail?.display ?? "…")
            row("路径", entry.path.expanded)
            row("备注", entry.note.isEmpty ? "（没有备注）" : entry.note)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Button("在访达里选中该目录") { store.open(entry) }
                Button("打开上一层目录") { store.revealParent(entry) }
                Button("复制完整路径") {
                    store.copyPath(entry)
                    store.say("路径已复制到剪贴板")
                }
                Button("编辑这条…") { edit() }
                    .help("会收起浮层，到控制台的条目页编辑")
            }
            .controlSize(.small)

            Text("以上动作只跳转、只改清单，不会删除文件。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
