import AppKit
import SwiftUI

final class ConsoleController {
    private let store: Store
    var window: NSWindow?
    private var editToken: Any?

    init(store: Store) {
        self.store = store
        // 卡片浮层里的「编辑…」走这里：浮层层级太高，内嵌的路径选择器会被它盖住，
        // 所以浮层只负责收起，编辑统一在控制台做。
        editToken = NotificationCenter.default.addObserver(
            forName: .dmEditEntry, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let entry = note.object as? Entry else { return }
            self.store.consoleTab = 0
            self.store.consoleEditing = EditTarget(draft: Draft(entry, isNew: false))
            self.show()
        }
    }

    deinit {
        if let editToken { NotificationCenter.default.removeObserver(editToken) }
    }

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DMLog.line("控制台 已显示 key=\(window?.isKeyWindow == true) 排队任务=\(store.pendingWork)")
        store.measureAll(refreshKnown: false)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "桌面地图 · 控制台"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 560, height: 420)
        w.contentView = PanelHostingView(rootView: ConsoleView(store: store))
        w.setFrameAutosaveName("DesktopMap.console")
        w.center()
        window = w
    }
}

// MARK: - root

struct ConsoleView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: store.binding({ store.consoleTab }, {
                    store.consoleTab = $0
                    store.touch()
                })) {
                    Text("条目 / 文件夹").tag(0)
                    Text("设置").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                if store.isMeasuring {
                    ProgressView().controlSize(.small)
                }
                Text(store.volumeSummary).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            if store.consoleTab == 0 {
                EntriesTab(store: store)
            } else {
                SettingsTab(store: store)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

// MARK: - entries tab

private struct EntriesTab: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("加到分组").font(.system(size: 10)).foregroundStyle(.secondary)
                Menu {
                    ForEach(groupChoices, id: \.self) { name in
                        Button(name) { store.consoleGroup = name; store.touch() }
                    }
                } label: {
                    Text(store.consoleGroup).font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                TextField("或打一个新分组名", text: store.binding({ store.consoleGroup }, {
                    store.consoleGroup = $0
                    store.touch()
                }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .font(.system(size: 11))
                .help("随便起名字：下一次添加/新建条目时，这个分组就出现了")
                Spacer()
                Button("新建条目") { DMLog.line("按钮 新建条目"); startBlank() }
                Button("添加文件夹…") { DMLog.line("按钮 添加文件夹"); addFolders() }
                Button("导入子文件夹…") { DMLog.line("按钮 导入子文件夹"); importChildren() }
                Button("扫描大目录") { DMLog.line("按钮 扫描大目录"); store.scanNow() }
                Button("重新测量") { DMLog.line("按钮 重新测量"); store.measureAll() }
            }
            .padding(10)

            if store.consoleScanOpen {
                CandidateList(store: store)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if let target = store.consoleEditing {
                EditorSheet(draft: target.draft, store: store, close: { store.consoleEditing = nil })
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.groups, id: \.name) { section in
                        HStack(spacing: 5) {
                            Text(section.name).font(.system(size: 11, weight: .bold))
                            Text("\(section.items.count) 条 · \(ByteFormat.string(store.bytes(of: section.items)))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                        ForEach(section.items) { entry in
                            ConsoleRow(entry: entry, store: store)
                        }
                    }
                }
                .padding(10)
            }

            Divider()
            HStack {
                Text(store.status.isEmpty ? "\(store.entries.count) 条，合计 \(ByteFormat.string(store.totalBytes))"
                     : store.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private var groupChoices: [String] {
        var names = store.allGroupNames
        for preset in ["缓存 · 可放心删", "应用数据 · 看清再动", "我的项目"] where !names.contains(preset) {
            names.append(preset)
        }
        return names
    }

    private func startBlank() {
        var entry = Entry()
        entry.group = store.consoleGroup
        store.consoleEditing = EditTarget(draft: Draft(entry, isNew: true))
    }

    private func addFolders() {
        let urls = FilePicker.folders(startingAt: "~/")
        DMLog.line("选择器 返回 \(urls.count) 个目录")
        guard !urls.isEmpty else { return }
        store.addFolders(urls, group: store.consoleGroup)
    }

    private func importChildren() {
        guard let url = FilePicker.folder(startingAt: "~/Documents") else {
            DMLog.line("选择器 取消/空")
            return
        }
        DMLog.line("选择器 选了 \(url.path)")
        store.importChildren(of: url, group: store.consoleGroup)
        store.consoleScanOpen = false
    }
}

private struct ConsoleRow: View {
    let entry: Entry
    @ObservedObject var store: Store

    private var detail: PathInfo? { store.info[entry.path] }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label.isEmpty ? (entry.path as NSString).lastPathComponent : entry.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(entry.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(detail?.display ?? "…")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(detail?.exists == false ? Color.red : Color.secondary)
                .frame(width: 68, alignment: .trailing)

            RiskChip(entry.risk)

            HStack(spacing: 2) {
                smallButton("跳转") { DMLog.line("行 跳转 \(entry.path)"); store.open(entry) }
                smallButton("编辑") {
                    DMLog.line("行 编辑 \(entry.path)")
                    store.consoleEditing = EditTarget(draft: Draft(entry, isNew: false))
                }
                smallButton("移除") { DMLog.line("行 移除 \(entry.path)"); store.remove(entry) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
    }

    private func smallButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .controlSize(.small)
            .buttonStyle(.borderless)
    }
}

// MARK: - settings tab

private struct SettingsTab: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section(header: Text("窗口")) {
                Picker("窗口层级", selection: store.binding({ store.pinIsDesktop }, {
                    store.setPin(desktop: $0)
                })) {
                    Text("贴在桌面（默认，会被别的窗口挡住）").tag(true)
                    Text("悬浮置顶（一直浮在上面）").tag(false)
                }
                .pickerStyle(.radioGroup)
                Toggle("开机自动启动", isOn: store.binding({ LoginItemHelper.isEnabled }, { wanted in
                    if wanted == LoginItemHelper.isEnabled { return }
                    if wanted { LoginItemHelper.enable() } else { LoginItemHelper.disable() }
                    store.touch()
                }))
            }

            Section(header: Text("屏幕")) {
                Picker("面板显示在", selection: store.binding({ store.screenID }, {
                    store.screenID = $0
                })) {
                    Text("自动（跟着上次的位置）").tag("")
                    ForEach(ScreenCatalog.all, id: \.id) { screen in
                        Text(screen.title).tag(screen.id)
                    }
                }
                Text("选好后面板立刻搬到那块屏的右上角；拔掉显示器会自动回到主屏。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("卡片浮层")) {
                Toggle("点状态栏图标弹出启动台式卡片", isOn: store.binding({ store.cardMode }, {
                    store.cardMode = $0
                }))
                Text("开着时状态栏图标左键出铺满屏幕的卡片网格、右键仍然是这个菜单。全局键 \(GlobalHotKey.display) 随时开合；浮层落在鼠标所在那块屏（上面「屏幕」指定过就听它的）。点卡片只在访达里选中该目录，ⓘ 看详情，✕ 撤掉卡片（不删文件），也可以从访达直接把文件夹拖到某个分组上。Esc 或点空白处关闭。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("分组管理")) {
                ForEach(store.allGroupNames, id: \.self) { name in
                    HStack(spacing: 6) {
                        Text("\(name)（\(store.count(in: name)) 条）")
                            .font(.system(size: 11))
                            .frame(width: 190, alignment: .leading)
                        TextField("改成什么名", text: store.binding({ store.renameBuffer[name] ?? "" }, {
                            store.renameBuffer[name] = $0
                            store.touch()
                        }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .font(.system(size: 11))
                        Button("改名") {
                            DMLog.line("按钮 分组改名 «\(name)»")
                            store.renameGroup(name)
                        }
                        .disabled((store.renameBuffer[name] ?? "").isEmpty)
                        Menu("并入…") {
                            ForEach(store.allGroupNames.filter { $0 != name }, id: \.self) { other in
                                Button(other) {
                                    DMLog.line("按钮 分组合并 «\(name)» → «\(other)»")
                                    store.moveAll(from: name, to: other)
                                }
                            }
                        }
                        .disabled(store.allGroupNames.count < 2)
                        Spacer()
                    }
                }
                Text("分组就是写在每条上的那个名字。想新建一组：在条目页的输入框里打个新名字，再加条目即可。改名 / 并组都是批量改这些条目身上的标签，文件一个都不动；某组的最后一条被移走或删掉后，这个组自动消失。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("数据")) {
                Picker("自动重新测量", selection: store.binding({ store.autoRefreshMinutes }, {
                    store.autoRefreshMinutes = $0
                })) {
                    Text("关闭").tag(0)
                    Text("每 5 分钟").tag(5)
                    Text("每 10 分钟").tag(10)
                    Text("每 30 分钟").tag(30)
                }
                Picker("扫描阈值", selection: store.binding({ store.scanThresholdMB }, {
                    store.scanThresholdMB = $0
                })) {
                    Text("50 MB").tag(50)
                    Text("100 MB").tag(100)
                    Text("300 MB").tag(300)
                    Text("1 GB").tag(1000)
                }
                Toggle("桌面面板显示备注行", isOn: store.binding({ store.showNotes }, {
                    store.showNotes = $0
                }))
            }

            Section(header: Text("磁盘概览")) {
                LabeledContent("本机", value: store.volumeSummary)
                LabeledContent("清单合计", value: ByteFormat.string(store.totalBytes))
                LabeledContent("标为可删", value: ByteFormat.string(store.deletableBytes))
                LabeledContent("条目数", value: "\(store.entries.count)")
            }

            Section(header: Text("文件与备份")) {
                Button("在访达中打开清单文件") {
                    DMLog.line("设置 显示清单文件")
                    NotificationCenter.default.post(name: .dmRevealList, object: nil)
                }
                Button("打开备份文件夹（现有 \(store.backupCount) 份）") {
                    DMLog.line("设置 打开备份文件夹")
                    NSWorkspace.shared.open(store.backupDirectory)
                }
                Text("每次改动清单前会自动留一份上一版，只保留最近 15 份。误删卡片、手滑恢复出厂，都能用下面那个按钮把前一份捞回来。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("恢复到最近一份备份") {
                    DMLog.line("设置 请求恢复备份 \(store.latestBackup?.lastPathComponent ?? "无")")
                    store.pendingConfirm = .restore
                }
                .disabled(store.latestBackup == nil)
                Button("恢复出厂清单", role: .destructive) {
                    DMLog.line("设置 请求恢复出厂")
                    store.pendingConfirm = .factory
                }
                Button("退出桌面地图") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12))
        .padding(10)
        .confirmationDialog("恢复到最近一份备份？",
                            isPresented: store.binding({ store.pendingConfirm == .restore }, {
                                if !$0 { store.pendingConfirm = .none }
                            }),
                            titleVisibility: .visible) {
            Button("覆盖当前清单", role: .destructive) {
                DMLog.line("设置 确认恢复备份")
                store.restoreFromLatestBackup()
                store.pendingConfirm = .none
            }
            Button("取消", role: .cancel) { store.pendingConfirm = .none }
        } message: {
            Text("当前清单会被 \(store.latestBackup?.lastPathComponent ?? "上一份备份") 覆盖。覆盖前还会再存一份当前版本，所以这一步本身也可撤销。")
        }
        .confirmationDialog("恢复出厂清单会清空你自己加的条目",
                            isPresented: store.binding({ store.pendingConfirm == .factory }, {
                                if !$0 { store.pendingConfirm = .none }
                            }),
                            titleVisibility: .visible) {
            Button("仍要恢复出厂", role: .destructive) {
                DMLog.line("设置 确认恢复出厂")
                store.restoreFactoryList()
                store.say("已恢复出厂清单（原清单已备份）")
                store.pendingConfirm = .none
            }
            Button("取消", role: .cancel) { store.pendingConfirm = .none }
        } message: {
            Text("清单会换回程序自带的默认那份。你加的条目、改的备注都会没，但会自动存成一份备份，之后可以用「恢复到最近一份备份」找回。")
        }
    }
}
