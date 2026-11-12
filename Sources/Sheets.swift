import AppKit
import ServiceManagement
import SwiftUI

enum LoginItemHelper {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func enable() {
        guard #available(macOS 13.0, *) else { return }
        do { try SMAppService.mainApp.register() } catch { report(error) }
    }

    static func disable() {
        guard #available(macOS 13.0, *) else { return }
        do { try SMAppService.mainApp.unregister() } catch { report(error) }
    }

    private static func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "开机自启设置失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - one entry form, used by both the panel sheet and the console

struct EditorSheet: View {
    let draft: Draft
    @ObservedObject var store: Store
    let close: () -> Void

    private var pathText: String { draft.entry.path }
    private var pathExists: Bool {
        !pathText.isEmpty && FileManager.default.fileExists(atPath: pathText.expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.added ? "添加条目" : "编辑条目")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 10)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 9) {
                GridRow {
                    Text("名称")
                    TextField("例如 JetBrains 索引缓存",
                              text: store.binding({ self.draft.entry.label }, {
                                  self.draft.entry.label = $0
                                  store.touch()
                              }))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("路径")
                    HStack(spacing: 5) {
                        TextField("~/Library/Caches/JetBrains",
                                  text: store.binding({ self.draft.entry.path }, {
                                      self.draft.entry.path = $0
                                      store.touch()
                                  }))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("选择…") { pickFolder() }
                    }
                }
                GridRow {
                    Text("")
                    HStack(spacing: 4) {
                        Circle()
                            .fill(pathText.isEmpty ? Color.secondary
                                    : (pathExists ? Color.green : Color.red))
                            .frame(width: 6, height: 6)
                        Text(pathHint)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("分组")
                    HStack(spacing: 5) {
                        TextField("缓存 / 我的项目 / …",
                                  text: store.binding({ self.draft.entry.group }, {
                                      self.draft.entry.group = $0
                                      store.touch()
                                  }))
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(store.allGroupNames, id: \.self) { name in
                                Button(name) {
                                    self.draft.entry.group = name
                                    store.touch()
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                GridRow {
                    Text("标注")
                    Picker("", selection: store.binding({ self.draft.entry.risk }, {
                        self.draft.entry.risk = $0
                        store.touch()
                    })) {
                        ForEach(Risk.allCases) { r in
                            Text(r.chip).tag(r)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                GridRow {
                    Text("备注")
                    TextField("这是什么、能不能删、删了有什么后果",
                              text: store.binding({ self.draft.entry.note }, {
                                  self.draft.entry.note = $0
                                  store.touch()
                              }),
                              axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }
            .font(.system(size: 11))

            Spacer(minLength: 10)

            HStack {
                if !draft.added {
                    Button("从清单移除", role: .destructive) {
                        store.remove(draft.entry)
                        close()
                    }
                }
                Spacer()
                Button("取消", action: close)
                    .keyboardShortcut(.cancelAction)
                Button(draft.added ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private var pathHint: String {
        if pathText.isEmpty { return "填路径，或用「选择…」挑目录" }
        return pathExists ? "路径存在" : "路径当前不存在（可能是软链指向没挂载的盘）"
    }

    private func save() {
        var entry = draft.entry
        entry.path = entry.path.trimmingCharacters(in: .whitespaces)
        entry.label = entry.label.trimmingCharacters(in: .whitespaces)
        guard !entry.path.isEmpty else {
            NSSound.beep()
            return
        }
        store.upsert(entry)
        close()
    }

    private func pickFolder() {
        guard let url = FilePicker.folder(startingAt: pathText) else { return }
        draft.entry.path = url.path.shortened
        store.touch()
    }
}

// MARK: - shared picker

enum FilePicker {
    /// 单选一个目录或文件，用于「选路径」和「导入子文件夹」的父目录。
    static func folder(startingAt tildePath: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选用"
        panel.level = .modalPanel
        let full = tildePath.expanded
        if !tildePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: isDirectoryPath(full)
                ? full
                : (full as NSString).deletingLastPathComponent)
        }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 多选目录，一次加入清单。
    static func folders(startingAt tildePath: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "加入清单"
        panel.message = "选中的文件夹会各加一条到清单"
        panel.level = .modalPanel
        let full = tildePath.expanded
        if !tildePath.isEmpty, isDirectoryPath(full) {
            panel.directoryURL = URL(fileURLWithPath: full)
        }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : []
    }
}

// MARK: - scan results, inline in the console

struct CandidateList: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("扫描结果").font(.system(size: 11, weight: .semibold))
                Text("≥\(store.scanThresholdMB)MB 且未收录").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("收起") { store.consoleScanOpen = false; store.touch() }
                    .controlSize(.small)
            }
            if store.candidates.isEmpty {
                Text(store.isMeasuring || store.isScanning ? "正在统计，稍等…" : store.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(store.candidates) { c in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    Text(c.path)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 4)
                                Text(c.group).font(.system(size: 9)).foregroundStyle(.secondary)
                                Text(ByteFormat.string(c.bytes))
                                    .font(.system(size: 11, design: .rounded))
                                    .frame(width: 68, alignment: .trailing)
                                if store.entries.contains(where: { $0.path == c.path }) {
                                    Text("已加入").font(.system(size: 10)).foregroundStyle(.green)
                                } else {
                                    Button("加入") { store.add(c) }.controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
                .frame(maxHeight: 190)
                Button("全部加入") {
                    for c in store.candidates where !store.entries.contains(where: { $0.path == c.path }) {
                        store.add(c)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
    }
}
