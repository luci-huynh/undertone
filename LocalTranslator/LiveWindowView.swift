import AppKit
import SwiftUI

/// Live window (PLAN §24.2 mockup): “LIVE … [Start/Stop]”, then EN above VI
/// for each segment, newest at the bottom. Movable, resizable, minimizable,
/// optionally kept on top; it never takes focus by itself (`LiveWindowController`).
struct LiveWindowView: View {
    @Bindable var session: LiveSession

    /// Privacy & Security › Screen & System Audio Recording (System Audio Recording Only).
    static let audioRecordingSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            LiveSubtitles(session: session)
            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 260, idealHeight: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            controls
            // Right under the picker: it says what the chosen source captures.
            if let note = session.source.note {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Own rows, so a long status never gets cut off.
            StatusRow(badge: statusBadge) {
                if session.status.needsAudioPermission {
                    Button("Open System Settings") { NSWorkspace.shared.open(Self.audioRecordingSettings) }
                }
            }
            if let problem = translationProblem {
                StatusRow(badge: StatusBadge(kind: .warning, text: "Translation: \(problem)")) {
                    if problem == TranslationError.runtimeUnavailable.message, OllamaAppLauncher.appURL != nil {
                        Button("Open Ollama") { OllamaAppLauncher.open() }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.status.isRunning ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("LIVE").font(.system(size: 13, weight: .bold))
            Spacer(minLength: 8)
            Picker("Source", selection: $session.source) {
                ForEach(LiveSource.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(session.status.isRunning)
            .help("Meeting app to listen to")
            if session.status.isRunning {
                // Not the default button: Return in the window must never end
                // the session and wipe its subtitles (L08 review).
                Button("Stop") { session.stop() }
                    .help("Stop listening and clear the subtitles")
            } else {
                Button("Start") { session.start() }
                    .keyboardShortcut(.defaultAction)
                    .help("Listen to \(session.source.title) and translate to Vietnamese")
            }
            Button {
                session.keepsWindowOnTop.toggle()
            } label: {
                Image(systemName: session.keepsWindowOnTop ? "pin.fill" : "pin.slash")
            }
            .buttonStyle(.borderless)
            .help(session.keepsWindowOnTop ? "Kept on top of other windows — click to let it go behind" : "Click to keep on top of other windows")
            .accessibilityLabel(session.keepsWindowOnTop ? "Keep on top: on" : "Keep on top: off")
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ProgressView(value: session.level)
                .frame(width: 60)
                .accessibilityLabel("Audio level")
            Text("English → Vietnamese on this Mac · the app's sound only, no microphone, nothing saved")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusBadge: StatusBadge {
        let waiting = session.translations.waitingCount
        let queue = waiting > 0 ? " · \(waiting) waiting to translate" : ""
        switch session.status {
        case .idle: return StatusBadge(kind: .neutral, text: session.status.label, symbol: "stop.circle")
        case .preparing: return StatusBadge(kind: .neutral, text: session.status.label, symbol: "hourglass")
        case .listening: return StatusBadge(kind: .ok, text: session.status.label + queue, symbol: "waveform")
        case .silent: return StatusBadge(kind: .neutral, text: session.status.label + queue, symbol: "speaker.slash")
        case .sourceNotRunning: return StatusBadge(kind: .warning, text: "\(session.source.title) isn't running")
        case .noAudioReceived, .failed: return StatusBadge(kind: .error, text: session.status.label)
        }
    }

    /// The newest translation outcome when it failed (e.g. Ollama quit), next
    /// to the capture status so “Listening” never hides it; the next success
    /// clears it.
    private var translationProblem: String? {
        for segment in session.transcript.segments.reversed() {
            switch session.translations.states[segment.id] {
            case .done: return nil
            case .failed(let message): return message
            default: continue
            }
        }
        return nil
    }
}

/// A status with its fix: the button sits beside a one-line status and moves
/// under a longer one, so neither is squeezed at the narrowest window.
private struct StatusRow<Action: View>: View {
    let badge: StatusBadge
    @ViewBuilder let action: () -> Action

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                badge.fixedSize()
                Spacer(minLength: 0)
                action()
            }
            VStack(alignment: .leading, spacing: 6) {
                badge
                action()
            }
        }
        .font(.callout)
        .controlSize(.small)
    }
}

/// The EN/VI pairs plus the English still being recognized.
private struct LiveSubtitles: View {
    let session: LiveSession
    @State private var followsOutput = true
    private static let bottomID = "bottom"

    var body: some View {
        let pairs = LivePairs.make(segments: session.transcript.segments, states: session.translations.states)
        // The content fills at least the visible height: on screen, selectable
        // text in a mostly empty scroll view was drawn upside down (user, L08).
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: at most 50 pairs, and a stable content height keeps
                // “back at the bottom → follow again” reliable (L05a).
                VStack(alignment: .leading, spacing: 14) {
                    if pairs.isEmpty && session.transcript.volatileText.isEmpty {
                        Text(session.status.isRunning ? "Listening for speech…" : "Choose the meeting app, then press Start.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .textSelection(.disabled)
                    }
                    ForEach(pairs) { pair in
                        LivePairView(english: pair.english, vietnamese: pair.vietnamese)
                            .textSelection(.enabled)
                    }
                    if !session.transcript.volatileText.isEmpty {
                        LivePairView(english: session.transcript.volatileText, vietnamese: nil)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
            }
            .modifier(BottomFollowTracker(followsOutput: $followsOutput, tolerance: 24))
            .onChange(of: pairs) { follow(proxy) }
            .onChange(of: session.transcript.volatileText) { follow(proxy) }
        }
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard followsOutput else { return }
        proxy.scrollTo(Self.bottomID, anchor: .bottom)
    }
}

/// “EN  text” above “VI  translation or its state”; `vietnamese == nil` is
/// the line still being recognized (no translation yet by design).
struct LivePairView: View {
    let english: String
    let vietnamese: LivePair.Vietnamese?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            line(label: "EN") {
                // The line still being recognized is dimmed until it settles.
                Text(english)
                    .foregroundStyle(vietnamese == nil ? Color.secondary : Color.primary.opacity(0.8))
            }
            if let vietnamese {
                line(label: "VI") { translation(vietnamese) }
            }
        }
        .font(.system(size: 16))
        .lineSpacing(3)
    }

    private func line(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
                .accessibilityHidden(true)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The translation stands out a little from the English: a muted slate
    /// blue, fixed rather than the system accent (a red, orange or graphite
    /// accent would read as an error or lose contrast; L08 review). About 8:1
    /// contrast on the light and 9:1 on the dark window background.
    static let vietnameseColor = Color(nsColor: NSColor(name: "LiveVietnamese") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.67, green: 0.80, blue: 0.92, alpha: 1)
            : NSColor(srgbRed: 0.13, green: 0.30, blue: 0.47, alpha: 1)
    })

    @ViewBuilder
    private func translation(_ state: LivePair.Vietnamese) -> some View {
        switch state {
        case .done(let text): Text(text).fontWeight(.medium).foregroundStyle(Self.vietnameseColor)
        case .translating(let text):
            Text(text.isEmpty ? "Translating…" : text).foregroundStyle(.secondary)
        case .waiting: Text("Waiting to translate…").foregroundStyle(.secondary)
        case .skipped: Text("Not translated — Live fell behind").foregroundStyle(.orange)
        case .failed(let message): Text(message).foregroundStyle(.red)
        }
    }
}

/// Live window: a normal window (minimize, resize, focus on click) that is
/// shown without activating the app, so opening it never takes focus from the
/// meeting app. “Keep on top” (default on) floats it above other windows, also
/// a full-screen meeting on the same Space. Frame remembered; closing stops
/// the session (PLAN §24.1).
final class LiveWindowController: NSObject, NSWindowDelegate {
    private let session: LiveSession
    private var window: NSWindow?

    init(session: LiveSession) {
        self.session = session
        super.init()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        applyLevel()
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        session.stop()
    }

    private func applyLevel() {
        guard let window else { return }
        window.level = session.keepsWindowOnTop ? .floating : .normal
        window.collectionBehavior = session.keepsWindowOnTop ? [.fullScreenAuxiliary, .moveToActiveSpace] : [.moveToActiveSpace]
    }

    /// Re-applies the level whenever the pin is toggled in the window.
    private func observeLevel() {
        withObservationTracking {
            _ = session.keepsWindowOnTop
        } onChange: { [self] in
            // The controller lives as long as the app; a strong capture is fine.
            Task { @MainActor in
                applyLevel()
                observeLevel()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: true
        )
        window.title = "Live Meeting Translation"
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 420, height: 260)
        let host = NSHostingView(rootView: LiveWindowView(session: session))
        // The window decides the size; SwiftUI fills it (free resizing).
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.delegate = self
        if !window.setFrameUsingName("LiveWindow") { window.center() }
        window.setFrameAutosaveName("LiveWindow")
        self.window = window
        observeLevel()
        return window
    }
}
