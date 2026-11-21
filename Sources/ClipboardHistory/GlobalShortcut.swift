import Carbon
import Foundation

@MainActor
final class GlobalShortcut {
    private static let identifier = EventHotKeyID(signature: 0x434C4950, id: 1)
    private let onPress: () -> Void
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init?(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let target = GetApplicationEventTarget()
        guard InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().handle(event)
            }
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else {
            return nil
        }
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_V), UInt32(controlKey | shiftKey),
            Self.identifier, target, UInt32(kEventHotKeyExclusive), &registration
        ) == noErr else {
            stop()
            return nil
        }
    }

    func stop() {
        if let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let result = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
        )
        guard result == noErr, identifier.signature == Self.identifier.signature,
              identifier.id == Self.identifier.id else { return OSStatus(eventNotHandledErr) }
        onPress()
        return noErr
    }
}
