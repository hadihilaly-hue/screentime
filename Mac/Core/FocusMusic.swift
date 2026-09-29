import AppKit

/// Loops a list of Spotify tracks during Lock In, using Spotify's AppleScript interface.
@MainActor
final class FocusMusic {
    static let spotifyID = "com.spotify.client"

    private let queue = DispatchQueue(label: "screentime.focus-music")
    private var tracks: [String] = []
    private var index = 0
    /// Spotify can report a different id than the one requested (relinked tracks), so remember what it plays.
    private var knownIDs: [String: Int] = [:]
    private var needsStart = false
    private var startedAt = Date.distantPast
    private var lastPosition = 0.0
    private var inFlight = false
    private var nextScheduled = false
    private(set) var isActive = false

    static var isSpotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyID) != nil
    }

    private var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyID).isEmpty
    }

    /// Accepts "https://open.spotify.com/track/<id>?si=…" or "spotify:track:<id>".
    static func uri(from link: String) -> String? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("spotify:track:") { return text }
        guard let url = URL(string: text), url.host?.hasSuffix("spotify.com") == true else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "track"), i + 1 < parts.count else { return nil }
        return "spotify:track:\(parts[i + 1])"
    }

    func start(_ links: [String]) {
        tracks = links.compactMap(Self.uri(from:))
        guard !tracks.isEmpty else { stop(); return }
        knownIDs = [:]
        for (i, uri) in tracks.enumerated() where knownIDs[uri] == nil { knownIDs[uri] = i }
        index = 0
        isActive = true
        needsStart = true
        if !isSpotifyRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        }
        poll()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        needsStart = false
        if isSpotifyRunning { run("tell application id \"\(Self.spotifyID)\" to pause") }
    }

    /// Called on every tracker tick while locked in: keeps the loop going.
    func poll() {
        guard isActive, !inFlight, isSpotifyRunning else { return }
        if needsStart {
            if Date().timeIntervalSince(startedAt) > 8 { play(index) }
            return
        }
        inFlight = true
        let source = """
        tell application id "\(Self.spotifyID)"
            set s to player state as string
            if s is "stopped" then return "stopped|||"
            return s & "|" & (id of current track) & "|" & (player position as string) & "|" & (duration of current track as string)
        end tell
        """
        run(source) { [weak self] result in
            self?.inFlight = false
            self?.handle(result)
        }
    }

    private func handle(_ result: String?) {
        guard isActive, let result else { return }
        let parts = result.components(separatedBy: "|")
        guard parts.count == 4 else { return }
        let state = parts[0]
        let id = parts[1]
        let position = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = (Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0) / 1000
        defer { lastPosition = position }

        if state == "stopped" { play(index); return }
        let sinceStart = Date().timeIntervalSince(startedAt)
        if sinceStart < 10 {
            if state == "playing", !id.isEmpty { knownIDs[id] = index }
            else if sinceStart > 5 { play(index) }
            return
        }
        guard let playingIndex = knownIDs[id] else {
            // Spotify moved on to something else (autoplay): back to the loop.
            play((index + 1) % tracks.count)
            return
        }
        index = playingIndex
        if state == "paused", position < 1, duration > 0, lastPosition > duration - 15 {
            play((index + 1) % tracks.count)
            return
        }
        let remaining = duration - position
        if state == "playing", duration > 0, remaining < 6, !nextScheduled {
            nextScheduled = true
            let next = (index + 1) % tracks.count
            DispatchQueue.main.asyncAfter(deadline: .now() + max(remaining - 0.3, 0)) { [weak self] in
                guard let self, self.isActive, self.nextScheduled else { return }
                self.play(next)
            }
        }
    }

    private func play(_ i: Int) {
        guard isActive, tracks.indices.contains(i) else { return }
        index = i
        needsStart = false
        nextScheduled = false
        startedAt = Date()
        lastPosition = 0
        run("tell application id \"\(Self.spotifyID)\" to play track \"\(tracks[i])\"")
    }

    private func run(_ source: String, completion: (@MainActor (String?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let text = error == nil ? result?.stringValue : nil
            Task { @MainActor in completion?(text) }
        }
    }
}
