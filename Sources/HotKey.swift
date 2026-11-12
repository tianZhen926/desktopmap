import AppKit
import Carbon.HIToolbox

/// 全局快捷键。用 Carbon 的 RegisterEventHotKey：系统级热键，不需要辅助功能权限，
/// 也不用 CGEventTap 那种要额外授权的事件隧道。
final class GlobalHotKey {
    fileprivate static let signature: OSType = 0x444D_484B   // 'DMHK'
    fileprivate static let hotKeyID: UInt32 = 1

    private let onFire: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var isRegistered: Bool { hotKeyRef != nil }

    init(keyCode: UInt32, modifiers: UInt32, name: String, onFire: @escaping () -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // C 回调不能捕获上下文，所以把自己以 unmanaged 指针传进去再取回来。
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotKey.signature else { return noErr }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { owner.onFire() }
            return noErr
        }, 1, &spec, userData, &handlerRef)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let error = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        DMLog.line(error == noErr ? "快捷键 已注册 \(name)" : "快捷键 注册失败 \(name) code=\(error)")
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

extension GlobalHotKey {
    static let display = "⌃⌥⌘M"

    /// ⌃⌥⌘M = 开合卡片浮层
    static func toggleCards(onFire: @escaping () -> Void) -> GlobalHotKey {
        GlobalHotKey(keyCode: UInt32(kVK_ANSI_M),
                     modifiers: UInt32(controlKey | optionKey | cmdKey),
                     name: display, onFire: onFire)
    }
}
