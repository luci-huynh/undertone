import Foundation

/// Meeting sources Live can listen to (L01 user decision: Teams, Google Meet
/// in Chrome, Slack huddles). Browsers and Electron apps play audio from
/// helper processes, so a source is its app plus those helpers (L01 probe).
nonisolated enum LiveSource: String, CaseIterable, Identifiable, Sendable {
    case teams
    case chrome
    case slack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teams: "Microsoft Teams"
        case .chrome: "Google Chrome (Google Meet)"
        case .slack: "Slack (huddles)"
        }
    }

    /// Shown under the picker; Chrome's helpers are shared by every tab.
    var note: String? {
        switch self {
        case .chrome: "Captures sound from every Chrome tab, not only Google Meet."
        case .teams, .slack: nil
        }
    }

    var appBundleID: String {
        switch self {
        case .teams: "com.microsoft.teams2"
        case .chrome: "com.google.Chrome"
        case .slack: "com.tinyspeck.slackmacgap"
        }
    }

    /// Tapped even when not running yet, so a helper that starts later is
    /// picked up (process restore by bundle ID).
    var knownBundleIDs: [String] {
        switch self {
        case .teams: [appBundleID]
        case .chrome, .slack: [appBundleID, appBundleID + ".helper"]
        }
    }

    /// The app itself or one of its helpers — never another app that merely
    /// shares a prefix (`com.google.Chrome.canary`, Brave, Safari).
    func owns(bundleID: String) -> Bool {
        switch self {
        case .teams: bundleID == appBundleID || bundleID.hasPrefix(appBundleID + ".")
        case .chrome, .slack: bundleID == appBundleID || bundleID.hasPrefix(appBundleID + ".helper")
        }
    }

    /// Bundle IDs to tap: the known ones plus matching processes seen now.
    func tapBundleIDs(running processes: [LiveAudioProcess]) -> [String] {
        let seen = processes.map(\.bundleID).filter(owns(bundleID:))
        return Array(Set(knownBundleIDs + seen)).sorted()
    }
}

/// A process Core Audio knows about (read-only list; no capture).
nonisolated struct LiveAudioProcess: Equatable, Sendable {
    let bundleID: String
    /// Core Audio reports the process is currently playing.
    let isPlaying: Bool
}

protocol LiveProcessListing {
    func audioProcesses() -> [LiveAudioProcess]
}
