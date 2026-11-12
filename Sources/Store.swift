import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let dmRefresh = Notification.Name("dmRefresh")
    static let dmAdd = Notification.Name("dmAdd")
    static let dmConsole = Notification.Name("dmConsole")
    static let dmRaise = Notification.Name("dmRaise")
    static let dmLower = Notification.Name("dmLower")
    static let dmTogglePin = Notification.Name("dmTogglePin")
    static let dmRevealList = Notification.Name("dmRevealList")
    static let dmPlace = Notification.Name("dmPlace")
    static let dmCardMode = Notification.Name("dmCardMode")
    static let dmHideCards = Notification.Name("dmHideCards")
    static let dmEditEntry = Notification.Name("dmEditEntry")
    static let dmToggleCards = Notification.Name("dmToggleCards")
    static let dmVolume = Notification.Name("dmVolume")
}

struct Candidate: Identifiable, Hashable {
    var id: String { path }
    let label: String
    let path: String
    let group: String
    let risk: Risk
    let bytes: Int64
}

final class Store: ObservableObject {
    static let shared = Store()

    // data
    var entries: [Entry] = []
    var info: [String: PathInfo] = [:]
    var isMeasuring = false
    var isScanning = false
    var volume: (free: Int64, total: Int64) = (0, 0)

    // ui state
    var filter = ""
    var collapsed: Set<String> = []
    var editing: EditTarget? { didSet { touch() } }
    var candidates: [Candidate] = []
    var pinIsDesktop = true

    // console state
    var consoleIsVisible = false
    var consoleTab = 0
    var consoleGroup = "我的项目"
    var consoleEditing: EditTarget? { didSet { touch() } }
    var consoleScanOpen = false
    var status = ""

    // 卡片模式（启动台样式浮层）
    var cardMode: Bool {
        didSet {
            UserDefaults.standard.set(cardMode, forKey: "dmCardMode")
            touch()
            NotificationCenter.default.post(name: .dmCardMode, object: nil)
        }
    }
    var cardFilter = ""
    /// 卡片浮层的入场开关：show 后下一拍置真，SwiftUI 才有 from→to 可插值。
    var cardsRevealed = false
    /// 顶部两个快捷筛选：清理时只想看能删的、或者只想看大块头。
    var cardOnlySafe = false { didSet { touch() } }
    var cardOnlyBig = false { didSet { touch() } }
    /// 右边详情条正在看的那条；nil = 收起。
    var cardDetail: Entry? { didSet { touch() } }
    /// 正在被拖拽悬停的分组名，用来高亮那一块，让「会落到哪一组」看得见。
    var cardDropTarget: String? { didSet { touch() } }

    /// 控制台里两个会动整份清单的操作，点下去先弹确认。
    enum PendingConfirm: String {
        case none, factory, restore
    }
    var pendingConfirm: PendingConfirm = .none { didSet { touch() } }

    // settings
    var autoRefreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoRefreshMinutes, forKey: "dmAutoRefresh")
            restartTimer()
            touch()
        }
    }
    var scanThresholdMB: Int {
        didSet {
            UserDefaults.standard.set(scanThresholdMB, forKey: "dmScanThreshold")
            touch()
        }
    }
    var showNotes: Bool {
        didSet {
            UserDefaults.standard.set(showNotes, forKey: "dmShowNotes")
            touch()
        }
    }

    /// 面板要贴在哪块屏；空 = 不强制搬动，跟着上次位置。
    var screenID: String {
        didSet {
            UserDefaults.standard.set(screenID, forKey: "dmScreenID")
            touch()
            NotificationCenter.default.post(name: .dmPlace, object: nil)
        }
    }

    private let collapsedKey = "dmCollapsedGroups"
    private let pinKey = "dmPinDesktop"
    private var timer: Timer?

    let listURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("list.json")
    }()

    private let workQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    private let scanQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    private init() {
        collapsed = Set(UserDefaults.standard.stringArray(forKey: collapsedKey) ?? [])
        pinIsDesktop = (UserDefaults.standard.object(forKey: pinKey) as? Bool) ?? true
        let d = UserDefaults.standard
        autoRefreshMinutes = d.object(forKey: "dmAutoRefresh") as? Int ?? 10
        scanThresholdMB = d.object(forKey: "dmScanThreshold") as? Int ?? 100
        showNotes = (d.object(forKey: "dmShowNotes") as? Bool) ?? true
        cardMode = (d.object(forKey: "dmCardMode") as? Bool) ?? false
        screenID = d.string(forKey: "dmScreenID") ?? ""
        reloadVolume()
    }

    func startTimers() { restartTimer() }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard autoRefreshMinutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoRefreshMinutes * 60),
                                     repeats: true) { [weak self] _ in
            self?.measureAll()
        }
    }

    func say(_ text: String) {
        status = text
        touch()
    }

    /// 唯一的失效通道：SwiftUI 收到 objectWillChange 后自己重算 body，
    /// 视图身份不变，所以控件不会被重复生成、点击也不会被旧视图吃掉。
    func touch() {
        objectWillChange.send()
    }

    // MARK: - persistence

    func load() {
        if let data = try? Data(contentsOf: listURL),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = list
            touch()
            return
        }
        if let seed = Bundle.main.url(forResource: "default_list", withExtension: "json"),
           let data = try? Data(contentsOf: seed),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = list
            persist()
            touch()
        }
    }

    private func persist() {
        backUpCurrentList()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: listURL, options: .atomic)
        }
    }

    func restoreFactoryList() {
        backUpCurrentList(tag: "-beforeFactory")
        entries = []
        info = [:]
        try? FileManager.default.removeItem(at: listURL)
        load()
        measureAll()
    }

    // MARK: - 备份

    /// 每次写盘前把上一版清单留在这里。清单是唯一一份数据，误删 ⊗ 连点、
    /// 手滑恢复出厂，都只能靠这份轮转备份捞回来。
    var backupDirectory: URL {
        listURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// 备份文件名里的时间戳；字典序等于时间序，所以排序就能取最新。
    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    private var backups: [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)) ?? [])
            .filter { $0.hasPrefix("list-") && $0.hasSuffix(".json") }
        return names.sorted(by: >).map { backupDirectory.appendingPathComponent($0) }
    }

    var latestBackup: URL? { backups.first }

    private func backUpCurrentList(tag: String = "") {
        let fm = FileManager.default
        guard fm.fileExists(atPath: listURL.path) else { return }
        try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let dest = backupDirectory.appendingPathComponent(
            "list-\(Self.stampFormat.string(from: Date()))\(tag).json")
        // 同一秒内的连续保存只留第一份，否则批量加条目会瞬间占满槽位。
        if tag.isEmpty, fm.fileExists(atPath: dest.path) { return }
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: listURL, to: dest)
        for old in backups.dropFirst(15) {
            try? fm.removeItem(at: old)
        }
    }

    /// 用最近一份备份盖回当前清单。
    func restoreFromLatestBackup() {
        guard let src = latestBackup else {
            say("还没有可恢复的备份")
            return
        }
        backUpCurrentList(tag: "-beforeRestore")
        let fm = FileManager.default
        try? fm.removeItem(at: listURL)
        do {
            try fm.copyItem(at: src, to: listURL)
        } catch {
            say("恢复失败：\(error.localizedDescription)")
            return
        }
        entries = []
        info = [:]
        load()
        measureAll()
        say("已恢复到 \(src.lastPathComponent)")
    }

    var backupCount: Int { backups.count }

    // MARK: - derived

    var groups: [(name: String, items: [Entry])] { grouped(by: filter) }

    /// 卡片浮层用独立的搜索词，免得把面板正在用的筛选一起改掉。
    var cardGroups: [(name: String, items: [Entry])] {
        let sections = grouped(by: cardFilter)
        guard cardOnlySafe || cardOnlyBig else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter { entry in
                if cardOnlySafe, entry.risk != .safe { return false }
                if cardOnlyBig, (info[entry.path]?.bytes ?? 0) < Self.bigBytes { return false }
                return true
            }
            return items.isEmpty ? nil : (section.name, items)
        }
    }

    static let bigBytes: Int64 = 1_000_000_000

    private func grouped(by query: String) -> [(name: String, items: [Entry])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var order: [String] = []
        var bucket: [String: [Entry]] = [:]
        for e in entries {
            if bucket[e.group] == nil { order.append(e.group) }
            if !q.isEmpty, !e.matches(q) { continue }
            bucket[e.group, default: []].append(e)
        }
        return order.compactMap { name in
            let items = bucket[name] ?? []
            return items.isEmpty ? nil : (name, items)
        }
    }

    var groupNames: [String] { groups.map(\.name) }

    var allGroupNames: [String] { Array(Set(entries.map(\.group))).sorted() }

    func count(in group: String) -> Int { entries.filter { $0.group == group }.count }

    /// 「分组管理」里每行正在输入的改名草稿；键是原组名。
    var renameBuffer: [String: String] = [:]

    /// 分组改名 = 把这一组条目的 group 字段一起换掉。
    /// 组本身不用单独删：最后一条被移走，这个组的名字就自动不存在了。
    func renameGroup(_ from: String) {
        let to = (renameBuffer[from] ?? "").trimmingCharacters(in: .whitespaces)
        guard !to.isEmpty else {
            say("新分组名没填")
            return
        }
        guard to != from else { return }
        guard !allGroupNames.contains(to) else {
            say("已经有一个叫「\(to)」的分组了")
            return
        }
        for i in entries.indices where entries[i].group == from {
            entries[i].group = to
        }
        renameBuffer[from] = nil
        if collapsed.remove(from) != nil {
            collapsed.insert(to)
            UserDefaults.standard.set(Array(collapsed), forKey: collapsedKey)
        }
        persist()
        touch()
        DMLog.line("分组改名 «\(from)» → «\(to)» 共 \(count(in: to)) 条")
        say("已把「\(from)」改名为「\(to)」")
    }

    /// 把条目从一组搬到另一组（分组名就是条目上的字段，所以「搬」=改字段）。
    func moveAll(from: String, to: String) {
        guard to != from, !to.isEmpty else { return }
        for i in entries.indices where entries[i].group == from {
            entries[i].group = to
        }
        persist()
        touch()
        DMLog.line("分组合并 «\(from)» → «\(to)»")
        say("已把「\(from)」并进「\(to)」")
    }

    var visibleEntries: [Entry] { entries }

    func bytes(of items: [Entry]) -> Int64 {
        items.reduce(Int64.zero) { $0 + (info[$1.path]?.bytes ?? 0) }
    }

    var totalBytes: Int64 { bytes(of: entries) }

    var deletableBytes: Int64 {
        entries.filter { $0.risk == .safe }.reduce(Int64.zero) {
            $0 + (info[$1.path]?.bytes ?? 0)
        }
    }

    var freeSpaceIsLow: Bool { volume.free < 30_000_000_000 }

    /// 状态栏用的一小截剩余空间，长了会挤占别的图标。
    var freeShort: String {
        guard volume.total > 0 else { return "" }
        let giga = volume.free / 1_000_000_000
        return giga >= 1 ? "剩 \(giga)G" : "剩 \(volume.free / 1_000_000)M"
    }

    var volumeSummary: String {
        guard volume.total > 0 else { return "磁盘信息不可用" }
        return "剩 " + ByteFormat.string(volume.free) + " / " + ByteFormat.string(volume.total)
    }

    func reloadVolume() {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let v = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return }
        volume = (Int64(v.volumeAvailableCapacityForImportantUsage ?? 0),
                  Int64(v.volumeTotalCapacity ?? 0))
        NotificationCenter.default.post(name: .dmVolume, object: nil)
    }

    // MARK: - editing

    func upsert(_ entry: Entry) {
        var item = entry
        item.path = item.path.trimmingCharacters(in: .whitespaces)
        item.group = item.group.isEmpty ? "其他" : item.group
        if let i = entries.firstIndex(where: { $0.id == item.id }) {
            entries[i] = item
        } else {
            entries.append(item)
        }
        persist()
        touch()
        measure(paths: [item.path])
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        touch()
    }

    /// 卡片浮层的「删除」：撤掉的只是这张可视化卡片，磁盘上的文件一个字都不动。
    /// 留一条贴回去的路，误点不用重新去找路径。
    private var lastRemoved: Entry?

    var canUndoRemove: Bool { lastRemoved != nil }

    func removeWithUndo(_ entry: Entry) {
        lastRemoved = entry
        remove(entry)
        say("已撤掉卡片「\(entry.title)」— 文件还在原位，没有删除")
    }

    func undoRemove() {
        guard let entry = lastRemoved else { return }
        lastRemoved = nil
        upsert(entry)
        say("已放回「\(entry.title)」")
    }

    func toggleCollapsed(_ name: String) {
        if collapsed.contains(name) { collapsed.remove(name) } else { collapsed.insert(name) }
        UserDefaults.standard.set(Array(collapsed), forKey: collapsedKey)
        touch()
    }

    /// 从菜单栏点某个分组：展开它、清掉筛选、把面板抬起来。
    func revealGroup(_ name: String) {
        collapsed.remove(name)
        UserDefaults.standard.set(Array(collapsed), forKey: collapsedKey)
        filter = ""
        touch()
        NotificationCenter.default.post(name: .dmRaise, object: nil)
    }

    func setFilter(_ text: String) {
        filter = text
        touch()
    }

    func setPin(desktop: Bool) {
        pinIsDesktop = desktop
        UserDefaults.standard.set(desktop, forKey: pinKey)
        touch()
    }

    var newEntry: Entry {
        var e = Entry()
        e.group = groups.first?.name ?? allGroupNames.first ?? "缓存"
        return e
    }

    // MARK: - opening

    func open(_ entry: Entry) {
        let full = entry.path.expanded
        guard FileManager.default.fileExists(atPath: full) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: full)])
    }

    func revealParent(_ entry: Entry) {
        let parent = (entry.path.expanded as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: parent))
    }

    func copyPath(_ entry: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path.expanded, forType: .string)
    }

    /// 卡片用真实文件图标。取一次存着：每个图标都要走一次 LaunchServices，
    /// 全屏网格一屏就有几十个，不缓存的话每次重绘都会卡一下。
    private var iconCache: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        let full = path.expanded
        if let cached = iconCache[full] { return cached }
        let image = NSWorkspace.shared.icon(forFile: full)
        image.size = NSSize(width: 58, height: 58)
        iconCache[full] = image
        return image
    }

    // MARK: - measurement

    func measureAll(refreshKnown: Bool = true) {
        let targets = refreshKnown ? entries : entries.filter { info[$0.path] == nil }
        measure(paths: targets.map(\.path))
    }

    /// 后台队列里还排着多少任务；一直降不下来就说明有 du 卡住了。
    var pendingWork: Int { workQueue.operationCount }

    func measure(paths: [String]) {
        let unique = Array(Set(paths)).sorted()
        guard !unique.isEmpty else { return }
        if !isMeasuring {
            isMeasuring = true
            touch()
        }
        DMLog.line("测量开始 \(unique.count) 条 排队=\(workQueue.operationCount)")
        let started = Date()
        let group = DispatchGroup()
        for path in unique {
            group.enter()
            workQueue.addOperation { [weak self] in
                guard let self else { group.leave(); return }
                let result = Self.stat(path)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.info[path] = result
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isMeasuring = false
            self.reloadVolume()
            DMLog.line("测量完成 用时 \(Int(Date().timeIntervalSince(started)))s 排队=\(self.workQueue.operationCount)")
            self.touch()
        }
    }

    func statSync(_ path: String) -> PathInfo { Self.stat(path) }

    private static func stat(_ path: String) -> PathInfo {
        var info = PathInfo()
        let full = path.expanded
        var isDir: ObjCBool = false
        info.exists = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
        guard info.exists else { return info }
        if isDir.boolValue {
            info.bytes = duBytes(full)
            info.failed = info.bytes == nil
            let keys: Set<URLResourceKey> = [.isUbiquitousItemKey]
            let values = try? URL(fileURLWithPath: full).resourceValues(forKeys: keys)
            info.ubiquitous = (values?.isUbiquitousItem ?? false) && (info.bytes ?? 1) == 0
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: full)
            info.bytes = (attrs?[.size] as? NSNumber)?.int64Value
            info.failed = info.bytes == nil
        }
        return info
    }

    private static func duBytes(_ path: String) -> Int64? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let out = Pipe()
        p.standardOutput = out
        // 必须是 /dev/null，不能是没人读的 Pipe：
        // du 遇到没权限的子目录会刷屏，管道 64KB 一满 du 就卡在 write 上，测量线程永久挂住。
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        var timedOut = false
        if done.wait(timeout: .now() + 90) == .timedOut {
            timedOut = true
            p.interrupt()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard !timedOut, p.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let head = text.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first
        guard let kb = Int64(head ?? "") else { return nil }
        return kb * 1024
    }

    // MARK: - scan

    private static let dotCacheNames = [
        ".npm", ".pnpm-store", ".gradle", ".cargo", ".cache", ".docker", ".ollama", ".m2",
    ]

    func scanNow() {
        if isScanning {
            say("上一轮扫描还在跑，稍等")
            return
        }
        candidates = []
        consoleScanOpen = true
        isScanning = true
        touch()
        runScan(minBytes: Int64(scanThresholdMB) * 1_000_000)
    }

    static let skipDirNames: Set<String> = [
        "node_modules", ".next", "target", "build", "dist", "__pycache__",
        ".venv", "venv", ".gradle", ".idea", ".cache",
    ]

    func addFolders(_ urls: [URL], group: String) {
        var paths: [String] = []
        for url in urls {
            let tilde = url.path.shortened
            if entries.contains(where: { $0.path == tilde }) { continue }
            var entry = Entry()
            entry.group = group
            entry.label = url.lastPathComponent
            entry.path = tilde
            entry.risk = .keep
            entries.append(entry)
            paths.append(tilde)
        }
        persist()
        touch()
        measure(paths: paths)
        say(paths.isEmpty ? "这些已经在清单里了" : "已加入 \(paths.count) 条到「\(group)」")
    }

    func importChildren(of url: URL, group: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        var children: [URL] = []
        for name in names {
            if name.hasPrefix(".") || Self.skipDirNames.contains(name) { continue }
            let child = url.appendingPathComponent(name)
            if isDirectoryPath(child.path) { children.append(child) }
        }
        guard !children.isEmpty else {
            say("\(url.lastPathComponent) 下面没有可导入的子文件夹")
            return
        }
        addFolders(children, group: group)
    }

    func runScan(minBytes: Int64) {
        // 单独的队列：整轮 du 可能跑几十秒，不能和逐条测量抢同 4 个槽位，
        // 否则「扫描大目录」会一直排在测量后面，看起来像按钮坏了。
        DMLog.line("扫描开始 阈值\(minBytes / 1_000_000)MB")
        scanQueue.addOperation { [weak self] in
            guard let self else { return }
            let known = Set(self.entries.map(\.path))
            let roots: [(String, String, Risk)] = [
                ("~/Library/Caches", "缓存 · 可放心删", .safe),
                ("~/Library/Application Support", "应用数据 · 看清再动", .caution),
            ]
            var found: [Candidate] = []

            func consider(_ tildePath: String, _ label: String, _ group: String, _ risk: Risk) {
                let full = tildePath.expanded
                guard !known.contains(tildePath), isDirectoryPath(full) else { return }
                if let bytes = Self.duBytes(full), bytes >= minBytes {
                    found.append(Candidate(label: label, path: tildePath, group: group,
                                           risk: risk, bytes: bytes))
                }
            }

            for (root, group, risk) in roots {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: root.expanded)) ?? []
                for name in names {
                    consider(root + "/" + name, name, group, risk)
                }
            }
            for name in Self.dotCacheNames {
                consider("~/" + name, name, "缓存 · 可放心删", .caution)
            }

            found.sort { $0.bytes > $1.bytes }
            DispatchQueue.main.async {
                DMLog.line("扫描完成 命中 \(found.count)")
                self.isScanning = false
                self.candidates = Array(found.prefix(40))
                self.say(self.candidates.isEmpty
                    ? "没有发现未收录的、≥\(self.scanThresholdMB)MB 的目录"
                    : "扫到 \(self.candidates.count) 个未收录的大目录")
            }
        }
    }

    func add(_ candidate: Candidate) {
        var entry = Entry()
        entry.group = candidate.group
        entry.label = candidate.label
        entry.path = candidate.path
        entry.note = "扫描发现，未收录过大目录"
        entry.risk = candidate.risk
        upsert(entry)
    }
}

private extension Entry {
    func matches(_ q: String) -> Bool {
        label.lowercased().contains(q) || path.lowercased().contains(q) || note.lowercased().contains(q)
    }
}
