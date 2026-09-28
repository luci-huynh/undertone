import Foundation

/// Selected text must never leave this Mac (PLAN F01/F08, AGENTS.md). Only
/// plain-HTTP loopback endpoints are accepted, and every request and
/// response URL is checked again, so a misconfiguration or a redirect cannot
/// reach another host.
nonisolated enum LocalEndpointPolicy {
    /// PLAN §2 names `http://localhost:11434`; the IPv4 loopback literal is
    /// used so name resolution cannot pick `::1` while Ollama listens on IPv4 only.
    static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!

    /// `URLComponents.host` keeps the brackets of an IPv6 literal.
    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]"]

    static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http",
              let host = components.host?.lowercased(),
              loopbackHosts.contains(host),
              components.user == nil, components.password == nil
        else { return false }
        return true
    }

    /// Parses a configured base URL; nil when it is not an allowed endpoint.
    static func baseURL(from string: String?) -> URL? {
        guard let string, !string.isEmpty else { return defaultBaseURL }
        guard let url = URL(string: string), isAllowed(url) else { return nil }
        return url
    }
}
