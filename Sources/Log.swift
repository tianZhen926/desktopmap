import AppKit

/// 排查用的落盘日志。我截不到屏幕，也拿不到辅助访问权限，
/// 所以把「鼠标落在哪个窗口/控件」和「按钮动作有没有真的执行」写进文件，事后直接读。
enum DMLog {
    static let url = Store.shared.listURL.deletingLastPathComponent()
        .appendingPathComponent("actions.log")

    static func line(_ text: String) {
        let stamp = Self.formatter.string(from: Date())
        let thread = Thread.isMainThread ? "主" : "其"
        guard let handle = Self.handle else { return }
        let bytes = Data(("\(stamp) [\(thread)] \(text)\n").utf8)
        handle.write(bytes)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// 全程只用一个句柄。每次新开 FileHandle 都停在文件头，会把上一行覆盖掉。
    private static let handle: FileHandle? = {
        if FileManager.default.fileExists(atPath: url.path) {
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil) ?? 0
            if size > 120_000 { try? FileManager.default.removeItem(at: url) }
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let opened = try? FileHandle(forWritingTo: url) else { return nil }
        opened.seekToEndOfFile()
        return opened
    }()
}

/// 记录所有进入窗口的鼠标事件：能看到命中的视图类型和窗口标题。
final class ClickRecorder {
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let window = event.window ?? NSApp.keyWindow
            let title = window?.title ?? "无窗口"
            let hit = window?.contentView?.hitTest(event.locationInWindow).map(Self.describe) ?? "nil"
            DMLog.line("鼠标 \(event.type == .leftMouseDown ? "左" : "右") «\(title)» 命中 \(hit) 层级=\(window?.level.rawValue ?? -999)")
            // 桌面层窗口平时不是 key、App 也不是前台：普通按钮能响应，
            // 但菜单/下拉/输入框必须有 key 窗口，否则点开就闪回、看着像按钮坏了。
            if let window, !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return event
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    private static func describe(_ view: NSView) -> String {
        var names: [String] = [String(describing: type(of: view))]
        var parent = view.superview
        var depth = 0
        while let p = parent, depth < 3 {
            names.append(String(describing: type(of: p)))
            parent = p.superview
            depth += 1
        }
        return names.joined(separator: "<-")
    }
}
