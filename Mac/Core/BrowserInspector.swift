import Foundation

/// Reads the active tab of supported browsers with AppleScript, off the main thread.
@MainActor
final class BrowserInspector {
    static let safariLike: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let chromiumLike: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func isBrowser(_ bundleID: String) -> Bool {
        safariLike.contains(bundleID) || chromiumLike.contains(bundleID)
    }

    private let queue = DispatchQueue(label: "screentime.browser-inspector")
    private var domains: [String: String] = [:]
    private var inFlight: Set<String> = []

    /// Last known domain of the browser's active tab; kicks off a refresh in the background.
    func domain(for bundleID: String) -> String? {
        refresh(bundleID)
        return domains[bundleID]
    }

    func closeActiveTab(bundleID: String) {
        let tab = Self.safariLike.contains(bundleID) ? "current tab" : "active tab"
        let source = "tell application id \"\(bundleID)\" to if (count of windows) > 0 then close \(tab) of front window"
        queue.async { _ = Self.run(source) }
        domains[bundleID] = nil
    }

    private func refresh(_ bundleID: String) {
        guard !inFlight.contains(bundleID) else { return }
        inFlight.insert(bundleID)
        let tab = Self.safariLike.contains(bundleID) ? "current tab" : "active tab"
        let source = "tell application id \"\(bundleID)\" to if (count of windows) > 0 then return URL of \(tab) of front window"
        queue.async { [weak self] in
            let url = Self.run(source)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(bundleID)
                self.domains[bundleID] = url.flatMap(Self.domain(from:))
            }
        }
    }

    nonisolated static func domain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let scheme = url.scheme, scheme.hasPrefix("http"),
              var host = url.host?.lowercased()
        else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    nonisolated private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}
