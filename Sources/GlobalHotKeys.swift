import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts. Carbon's hotkey API is the one that works without the
/// accessibility permission an event tap would demand.
final class GlobalHotKeys {
    private var actions: [UInt32: () -> Void] = [:]
    private var registered: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue().actions[id.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            EventHotKeyID(signature: OSType(0x5354_4E43), id: nextID),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        actions[nextID] = action
        registered.append(reference)
        nextID += 1
        return true
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        actions.removeAll()
    }

    deinit { unregisterAll() }
}
