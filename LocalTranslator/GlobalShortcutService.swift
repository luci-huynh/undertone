import Carbon.HIToolbox
import Observation
import os

struct HotKeyCombination: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    static let optionT = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(optionKey),
        display: "⌥T"
    )

    /// Registered only while the popup is visible.
    static let escape = HotKeyCombination(
        keyCode: UInt32(kVK_Escape),
        carbonModifiers: 0,
        display: "Esc"
    )
}

enum HotKeyPhase: Equatable {
    case pressed, released
}

enum HotKeyRegistrationError: Error, Equatable {
    /// Another process already holds the combination exclusively.
    case conflict
    case failed(OSStatus)
}

protocol HotKeyRegistering: AnyObject {
    func register(_ combination: HotKeyCombination, handler: @escaping (HotKeyPhase) -> Void) throws
    func unregister()
}

/// System-wide hot key via Carbon. Needs no Accessibility or Input Monitoring
/// permission, consumes the key event (no stray character in the source app)
/// and does not activate this app. Exclusive registration surfaces conflicts.
/// Each registrar has its own hot key ID so several can coexist.
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    nonisolated private static let signature: OSType = 0x4C54_726E // "LTrn"
    private static var nextID: UInt32 = 1

    nonisolated private let id: UInt32

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: ((HotKeyPhase) -> Void)?

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    func register(_ combination: HotKeyCombination, handler: @escaping (HotKeyPhase) -> Void) throws {
        unregister()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { throw HotKeyRegistrationError.failed(installStatus) }

        let registerStatus = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            throw registerStatus == OSStatus(eventHotKeyExistsErr)
                ? HotKeyRegistrationError.conflict
                : HotKeyRegistrationError.failed(registerStatus)
        }
        self.handler = handler
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        handler = nil
    }

    private func deliver(_ phase: HotKeyPhase) {
        handler?(phase)
    }

    /// Carbon delivers application-target events on the main thread. Every
    /// registrar's handler sees every hot key event; one that is not ours must
    /// return eventNotHandledErr so the next handler receives it.
    nonisolated private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        guard status == noErr, hotKeyID.signature == signature, hotKeyID.id == registrar.id else {
            return OSStatus(eventNotHandledErr)
        }
        let phase: HotKeyPhase = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
        MainActor.assumeIsolated {
            registrar.deliver(phase)
        }
        return noErr
    }
}

enum ShortcutStatus: Equatable {
    case inactive
    case registered
    case conflict
    case failed(OSStatus)

    var label: String {
        switch self {
        case .inactive: "Chưa bật"
        case .registered: "Đã đăng ký"
        case .conflict: "Bị trùng với app khác"
        case .failed(let code): "Lỗi đăng ký (\(code))"
        }
    }

    /// The menu is English (PLAN F07); Settings uses `label`.
    var menuLabel: String {
        switch self {
        case .inactive: "not active"
        case .registered: "active"
        case .conflict: "used by another app"
        case .failed(let code): "couldn't register (\(code))"
        }
    }
}

@Observable
final class GlobalShortcutService {
    let combination: HotKeyCombination
    private let registrar: any HotKeyRegistering
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.Undertone", category: "shortcut")

    private(set) var status: ShortcutStatus = .inactive
    /// Presses this launch; each press also calls `onTrigger`.
    private(set) var triggerCount = 0
    /// Holding the keys must produce one trigger; re-arm only after release.
    @ObservationIgnored private var isHeld = false
    @ObservationIgnored var onTrigger: (() -> Void)?

    init(combination: HotKeyCombination = .optionT, registrar: any HotKeyRegistering) {
        self.combination = combination
        self.registrar = registrar
    }

    func start() {
        guard status != .registered else { return }
        do {
            try registrar.register(combination) { [weak self] phase in self?.handle(phase) }
            status = .registered
        } catch HotKeyRegistrationError.conflict {
            status = .conflict
        } catch HotKeyRegistrationError.failed(let code) {
            status = .failed(code)
        } catch {
            status = .failed(OSStatus(paramErr))
        }
        logger.notice("Shortcut registration: \(self.status.label, privacy: .public)")
    }

    func stop() {
        registrar.unregister()
        isHeld = false
        status = .inactive
    }

    func handle(_ phase: HotKeyPhase) {
        switch phase {
        case .pressed:
            guard status == .registered, !isHeld else { return }
            isHeld = true
            triggerCount += 1
            logger.notice("Shortcut triggered, count \(self.triggerCount, privacy: .public)")
            onTrigger?()
        case .released:
            isHeld = false
        }
    }
}
