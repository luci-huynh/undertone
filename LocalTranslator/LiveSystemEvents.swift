import AppKit
import CoreAudio
import Foundation

/// System changes after which the capture is rebuilt (L06): the aggregate
/// device is clocked by the default output, which can change or vanish
/// (headphones), and audio devices can be reset by sleep.
enum LiveSystemEvent: Equatable {
    case outputDeviceChanged
    case didWake
}

@MainActor
protocol LiveSystemEventSource: AnyObject {
    func start(_ handler: @escaping (LiveSystemEvent) -> Void)
    func stop()
}

/// Core Audio listeners on the system object plus the wake notification.
final class CoreAudioSystemEvents: LiveSystemEventSource {
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var wakeObserver: NSObjectProtocol?

    func start(_ handler: @escaping (LiveSystemEvent) -> Void) {
        stop()
        // Not kAudioHardwarePropertyDevices: rebuilding our own private
        // aggregate changes the device list, which would restart capture in a
        // loop (L08 review). A removed device changes the defaults anyway.
        for selector in [kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in handler(.outputDeviceChanged) }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler(.didWake) }
        }
    }

    func stop() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listeners.removeAll()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }
}

/// No system events (tests, macOS below 26).
final class NoLiveSystemEvents: LiveSystemEventSource {
    func start(_ handler: @escaping (LiveSystemEvent) -> Void) {}
    func stop() {}
}
