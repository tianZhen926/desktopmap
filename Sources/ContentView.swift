import AppKit
import SwiftUI

final class Draft {
    var entry: Entry
    var added: Bool
    init(_ entry: Entry, isNew: Bool) {
        self.entry = entry
        self.added = isNew
    }
}

struct EditTarget: Identifiable {
    let id = UUID()
    let draft: Draft
}

extension Store {
    func binding<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}

struct ContentView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 340, minHeight: 400)
        .background(.regularMaterial)
        .sheet(item: store.binding({ store.editing }, { store.editing = $0 }),
               onDismiss: { NotificationCenter.default.post(name: .dmLower, object: nil) })
        { target in
            EditorSheet(draft: target.draft, store: store, close: { store.editing = nil })
                .frame(minWidth: 380, idealWidth: 400, minHeight: 320)
        }
        .onAppear {
            store.measureAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dmRefresh)) { _ in store.measureAll() }
        .onReceive(NotificationCenter.default.publisher(for: .dmAdd)) { _ in startEditing(store.newEntry) }
    }

    private func startEditing(_ entry: Entry) {
        let isNew = !store.entries.contains(where: { $0.id == entry.id })
        raise()
        store.editing = EditTarget(draft: Draft(entry, isNew: isNew))
    }

    // MARK: - header

    private var header: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("桌面地图").font(.system(size: 13, weight: .bold))
                Spacer()
                if store.isMeasuring {
                    ProgressView().controlSize(.small)
                }
                Text(store.deletableBytes > 0 ? "可回收 \(ByteFormat.string(store.deletableBytes))" : "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(store.volumeSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(store.freeSpaceIsLow ? Color.red : Color.secondary)
                    .help("本机磁盘剩余空间")
            }
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("筛选名称 / 路径 / 备注",
                          text: store.binding({ store.filter }, { store.setFilter($0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !store.filter.isEmpty {
                    Button { store.setFilter("") } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                toolButton("arrow.clockwise", "重新测量 (⌘R)") { store.measureAll() }
                toolButton("plus", "添加条目 (⌘N)") { startEditing(store.newEntry) }
                toolButton("slider.horizontal.3", "控制台 (⌘,)") { openConsole() }
                Menu {
                    Button(store.pinIsDesktop ? "改为悬浮置顶" : "改为贴在桌面") {
                        NotificationCenter.default.post(name: .dmTogglePin, object: nil)
                    }
                    loginItemButton
                    Button("在访达中打开清单文件") {
                        NotificationCenter.default.post(name: .dmRevealList, object: nil)
                    }
                    Divider()
                    Button("控制台…", action: openConsole)
                    Button("退出桌面地图") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var loginItemButton: some View {
        Button(LoginItemHelper.isEnabled ? "关闭开机自启" : "设为开机自启") {
            if LoginItemHelper.isEnabled { LoginItemHelper.disable() } else { LoginItemHelper.enable() }
            store.touch()
        }
    }

    private func toolButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { DMLog.line("面板按钮 \(help)"); action() }) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func raise() {
        NotificationCenter.default.post(name: .dmRaise, object: nil)
    }

    private func openConsole() {
        NotificationCenter.default.post(name: .dmConsole, object: nil)
    }

    // MARK: - list

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(store.groups, id: \.name) { section in
                    SectionHeader(
                        name: section.name,
                        count: section.items.count,
                        bytes: store.bytes(of: section.items),
                        collapsed: store.collapsed.contains(section.name)
                    ) { store.toggleCollapsed(section.name) }

                    if !store.collapsed.contains(section.name) {
                        ForEach(section.items) { entry in
                            EntryRow(entry: entry, store: store, edit: { startEditing(entry) })
                        }
                        Color.clear.frame(height: 6)
                    }
                }
                if store.groups.isEmpty {
                    Text(store.entries.isEmpty ? "清单是空的，点上面的 ＋ 添加" : "没有匹配的条目")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - footer

    private var footer: some View {
        HStack {
            Text("\(store.entries.count) 条 · 合计 \(ByteFormat.string(store.totalBytes))")
            Spacer()
            Text("只跳转 · 不删除")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - rows

struct SectionHeader: View {
    let name: String
    let count: Int
    let bytes: Int64
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(name).font(.system(size: 11, weight: .semibold))
                Text("\(count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Text(ByteFormat.string(bytes)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EntryRow: View {
    let entry: Entry
    @ObservedObject var store: Store
    let edit: () -> Void

    private var detail: PathInfo? { store.info[entry.path] }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.label.isEmpty ? shortPath : entry.label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    RiskChip(entry.risk)
                    Text(sizeText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(sizeColor)
                        .frame(width: 64, alignment: .trailing)
                }
                Text(entry.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !entry.note.isEmpty, store.showNotes {
                    Text(entry.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.path.expanded)
        .contextMenu {
            Button("在访达中打开") { open() }
            Button("打开所在目录") { store.revealParent(entry) }
            Button("复制路径") { store.copyPath(entry) }
            Divider()
            Button("编辑…", action: edit)
            Button("从清单移除（不删文件）", role: .destructive) { store.remove(entry) }
        }
    }

    private var shortPath: String { (entry.path as NSString).lastPathComponent }

    private var sizeText: String { detail?.display ?? "…" }

    private var sizeColor: Color {
        guard let detail else { return .secondary }
        if !detail.exists { return .red }
        if detail.failed { return .orange }
        if detail.ubiquitous { return .secondary }
        return (entry.risk == .safe && (detail.bytes ?? 0) >= 200_000_000) ? .primary : .secondary
    }

    private func open() {
        if detail?.exists == false {
            NSSound.beep()
            return
        }
        store.open(entry)
    }
}

struct RiskChip: View {
    let risk: Risk

    init(_ risk: Risk) { self.risk = risk }

    var body: some View {
        Text(risk.chip)
            .font(.system(size: 8.5, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .keep: return .purple
        }
    }
}
