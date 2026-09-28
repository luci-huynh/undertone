import AppKit
import Observation
import os

enum RuntimeStatus: Equatable {
    case notChecked
    case connected(version: String)
    /// Nothing answers on the endpoint (PLAN §14 “Ollama is not running.”).
    case notRunning
    /// Something answered but not with Ollama's API.
    case invalidResponse
    /// Configured endpoint is not loopback; nothing was sent.
    case endpointRejected

    /// Menu wording follows PLAN F07 (“Ollama: Connected”).
    var label: String {
        switch self {
        case .notChecked: "Checking…"
        case .connected: "Connected"
        case .notRunning: "Not running"
        case .invalidResponse: "Unexpected response"
        case .endpointRejected: "Endpoint not local"
        }
    }
}

enum ModelStatus: Equatable {
    case unknown
    case installed
    /// PLAN §14 “Translation model is not installed.” No background download.
    case missing
    /// Cloud tags would send text off this Mac.
    case cloudRejected
}

/// Knows whether Ollama answers and the configured model is installed
/// (PLAN F01). Checks at launch, every `pollInterval`, and on demand; each
/// check is two small GETs to loopback. Stores only configuration.
@Observable
final class OllamaReadinessService {
    private(set) var runtime: RuntimeStatus = .notChecked
    private(set) var model: ModelStatus = .unknown
    /// Local (non-cloud) models Ollama reports, for the model picker.
    private(set) var installedLocalModels: [String] = []
    private(set) var configuration: TranslationModelConfiguration

    @ObservationIgnored let client: OllamaClient?
    @ObservationIgnored private let settings: any ModelSettingsStoring
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private let logger = Logger(subsystem: "local.chienhuynh.LocalTranslator", category: "ollama")

    init(settings: any ModelSettingsStoring, transport: any HTTPTransport, pollInterval: Duration = .seconds(20)) {
        self.settings = settings
        self.pollInterval = pollInterval
        configuration = TranslationModelConfiguration(tag: settings.modelTag)
        client = LocalEndpointPolicy.baseURL(from: settings.baseURLString).flatMap {
            try? OllamaClient(baseURL: $0, transport: transport)
        }
    }

    var isReady: Bool {
        if case .connected = runtime, model == .installed { return true }
        return false
    }

    var modelLabel: String {
        switch model {
        case .unknown, .installed: configuration.tag
        case .missing: "\(configuration.tag) (not installed)"
        case .cloudRejected: "\(configuration.tag) (cloud, refused)"
        }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previous = (runtime, model)

        guard let client else {
            runtime = .endpointRejected
            model = .unknown
            installedLocalModels = []
            logChange(from: previous)
            return
        }
        do {
            let version = try await client.version()
            let models = try await client.installedModels()
            runtime = .connected(version: version)
            installedLocalModels = models.filter(\.isLocal).map(\.name).sorted()
            updateModelStatus()
        } catch OllamaError.runtimeUnavailable {
            runtime = .notRunning
            model = .unknown
            installedLocalModels = []
        } catch is CancellationError {
            return
        } catch {
            runtime = .invalidResponse
            model = .unknown
            installedLocalModels = []
        }
        logChange(from: previous)
    }

    func selectModel(_ tag: String) {
        settings.modelTag = tag
        configuration = TranslationModelConfiguration(tag: tag)
        updateModelStatus()
    }

    #if DEBUG
    /// Settings “Dịch thử” (Debug only): one synthetic sentence, non-streaming.
    static let sampleSentence = "The payment has been processed."

    func translateSample() async -> Result<(text: String, milliseconds: Int), OllamaError> {
        guard let client else { return .failure(.endpointRejected) }
        let started = Date()
        do {
            let text = try await client.chat(
                model: configuration.tag,
                messages: configuration.messages(translating: Self.sampleSentence, direction: .englishToVietnamese),
                // A request without keep_alive resets Ollama's unload timer to 5 min.
                keepAlive: OllamaTranslationService.keepAlive,
                // Same context as ⌥T; a different one would reload the model.
                options: TranslationBudget.options
            )
            return .success((text.trimmingCharacters(in: .whitespacesAndNewlines), Int(Date().timeIntervalSince(started) * 1000)))
        } catch let error as OllamaError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }
    #endif

    private func updateModelStatus() {
        guard case .connected = runtime else {
            model = configuration.isCloud ? .cloudRejected : .unknown
            return
        }
        if configuration.isCloud {
            model = .cloudRejected
        } else {
            let wanted = ModelTag.normalized(configuration.tag)
            model = installedLocalModels.contains { ModelTag.normalized($0) == wanted } ? .installed : .missing
        }
    }

    private func logChange(from previous: (RuntimeStatus, ModelStatus)) {
        guard previous != (runtime, model) else { return }
        logger.notice("Ollama \(self.runtime.label, privacy: .public), model \(String(describing: self.model), privacy: .public)")
    }
}

/// PLAN F07 “Open Ollama”.
enum OllamaAppLauncher {
    static let bundleIdentifier = "com.electron.ollama"

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func open() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
