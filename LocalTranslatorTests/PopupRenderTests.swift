import AppKit
import SwiftUI
import Testing
@testable import Undertone

/// Renders the popup to PNG for visual review (S25 UI checklist). Runs only
/// with TEST_RUNNER_LT_RENDER_DIR=<dir>; synthetic text only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LT_RENDER_DIR"] != nil))
struct PopupRenderTests {
    private static let french = TranslationDirection(source: TranslationLanguage(code: "zh-Hans"), target: .vietnamese)

    private static let cases: [(String, PopupContent)] = [
        ("done-short", PopupContent(title: "English → Vietnamese", body: "Thanh toán này đã được xử lý.", phase: .done, alternateDirection: .vietnameseToEnglish, offersRetranslate: true)),
        ("done-widest-row", PopupContent(title: "Chinese, Simplified → Vietnamese", body: "Xin chào", phase: .done, alternateDirection: french.switched, offersRetranslate: true)),
        ("loading", PopupContent(title: "English → Vietnamese (guessed)", body: "", phase: .loading, alternateDirection: .vietnameseToEnglish)),
        ("streaming-long", PopupContent(title: "Vietnamese → English", body: String(repeating: "Người dùng cần kiểm tra lại báo cáo quyết toán trước cuối ngày. Ỹ ỹ Ậ ậ Ữ ữ. ", count: 12), phase: .streaming, alternateDirection: .englishToVietnamese)),
        ("failed-partial-worst", PopupContent(title: "Chinese, Simplified → Vietnamese (guessed)", body: "Xin chào, đây là một phần bản dịch", phase: .failed, action: .retry, message: "Ollama: model requires more system memory (9.8 GiB) than is available (7.1 GiB)", alternateDirection: french.switched)),
        ("failed-empty", PopupContent(title: "English → Vietnamese", body: "", phase: .failed, action: .retry, message: "Ollama is not running.", alternateDirection: .vietnameseToEnglish)),
        ("notice-permission", PopupContent(title: "", body: "Undertone needs Accessibility permission to read selected text.", phase: .notice, action: .openAccessibilitySettings)),
    ]

    @Test func renderPopups() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LT_RENDER_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in Self.cases {
            let layout = PopupMetrics.layout(for: content.body, maxSize: CGSize(width: 1000, height: 800))
            for scheme in [ColorScheme.light, .dark] {
                let view = TranslationPopupView(content: content, width: layout.width, bodyHeight: layout.bodyHeight, onCopy: {}, onAction: { _ in }, onClose: {})
                    .padding(12)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.93))
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
