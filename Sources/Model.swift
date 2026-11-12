import AppKit
import Foundation

enum Risk: String, Codable, CaseIterable, Identifiable {
    case safe
    case caution
    case keep

    var id: String { rawValue }

    var chip: String {
        switch self {
        case .safe: return "可删"
        case .caution: return "谨慎"
        case .keep: return "别动"
        }
    }
}

struct Entry: Identifiable, Hashable {
    var id = UUID()
    var group: String = "其他"
    var label: String = ""
    var path: String = ""
    var note: String = ""
    var risk: Risk = .caution

    var title: String {
        label.isEmpty ? (path as NSString).lastPathComponent : label
    }
}

extension Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, group, label, path, note, risk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "其他"
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        risk = try c.decodeIfPresent(Risk.self, forKey: .risk) ?? .caution
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(group, forKey: .group)
        try c.encode(label, forKey: .label)
        try c.encode(path, forKey: .path)
        try c.encode(note, forKey: .note)
        try c.encode(risk, forKey: .risk)
    }
}

struct PathInfo: Hashable {
    var exists = false
    var bytes: Int64?
    var failed = false
    var ubiquitous = false

    var display: String {
        if !exists { return "不存在" }
        if ubiquitous && (bytes ?? 0) == 0 { return "☁︎ 云端" }
        if failed { return "?" }
        guard let bytes else { return "…" }
        return ByteFormat.string(bytes)
    }

    var displayIsWarning: Bool { !exists || failed }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: bytes)
    }
}

extension String {
    var expanded: String { (self as NSString).expandingTildeInPath }

    var shortened: String {
        let home = NSHomeDirectory()
        return hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }
}

func isDirectoryPath(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

/// 接进来的屏幕列表。用 NSScreenNumber 当稳定标识，分辨率/序号只做展示。
enum ScreenCatalog {
    static func id(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return String(number?.uint32Value ?? 0)
    }

    /// 菜单栏所在那块屏才是通常说的「主屏」。
    /// 不能用 NSScreen.main —— 它的定义是「当前焦点窗口所在的屏」，
    /// 控制台开到另一块屏时它就跟着跳，拿它标主屏会让屏幕顺序看起来变了。
    static var primary: NSScreen? { NSScreen.screens.first }

    static var all: [(id: String, title: String)] {
        let base = primary
        return NSScreen.screens.enumerated().map { pair in
            let screen = pair.element
            let frame = screen.frame
            let scale = (screen.backingScaleFactor * 100).rounded() / 100
            return (id(screen),
                    "\(pair.offset + 1) 号屏 \(Int(frame.width))×\(Int(frame.height)) @\(scale)x · \(whereIs(it: screen, relativeTo: base))")
        }
    }

    private static func whereIs(it screen: NSScreen, relativeTo base: NSScreen?) -> String {
        guard let base else { return "未知位置" }
        if screen === base { return "主屏（有菜单栏）" }
        let dx = screen.frame.midX - base.frame.midX
        let dy = screen.frame.midY - base.frame.midY
        if abs(dx) >= abs(dy) { return dx < 0 ? "在主屏左边" : "在主屏右边" }
        return dy > 0 ? "在主屏上边" : "在主屏下边"
    }

    static func screen(forID choice: String) -> NSScreen? {
        guard !choice.isEmpty else { return nil }
        return NSScreen.screens.first { id($0) == choice }
    }
}
