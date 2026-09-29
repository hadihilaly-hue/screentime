import CryptoKit
import Foundation

struct LockInSettings: Codable, Equatable {
    var minutes = 50
    /// Blocked while locked in (Mac and iPhone), and on iPhone kept locked until an unlock code is entered.
    var blockedCategories: [String] = ["Social", "Entertainment", "Games"]
    var blockedTargets: [Target] = []
    var allowedTargets: [Target] = []
    var targetNames: [String: String] = [:]
    var playMusic = true
    var tracks: [String] = LockInSettings.defaultTracks
    /// iPhone: blocked categories stay locked outside Lock In until a Mac unlock code is entered.
    var requireCode = false
    var rewardMinutes = 20
    /// Shared between the Mac (which issues unlock codes) and the iPhone (which checks them).
    var pairingKey = ""

    static let defaultTracks = [
        "https://open.spotify.com/track/6BQFr6bAkBqTA4m3A0rKY3",
        "https://open.spotify.com/track/3dqHiEY4imK4a1EDLRVUtj",
    ]
    static let musicApps: Set<String> = ["com.spotify.client", "com.apple.Music", "spotify", "music", "apple music"]
    static let giveUpPhrase = "I am giving up on my work"
    static let trackNames = [
        "spotify:track:6BQFr6bAkBqTA4m3A0rKY3": "Experience – Ludovico Einaudi",
        "spotify:track:3dqHiEY4imK4a1EDLRVUtj": "Solas – Jamie Duffy",
    ]
    /// One-tap picks for the usual distractions.
    static let popular: [(name: String, site: String)] = [
        ("Instagram", "instagram.com"), ("YouTube", "youtube.com"), ("Snapchat", "snapchat.com"),
        ("TikTok", "tiktok.com"), ("X", "x.com"), ("Reddit", "reddit.com"), ("Netflix", "netflix.com"),
        ("Discord", "discord.com"), ("Roblox", "roblox.com"), ("Twitch", "twitch.tv"),
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LockInSettings()
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? d.minutes
        blockedCategories = try c.decodeIfPresent([String].self, forKey: .blockedCategories) ?? d.blockedCategories
        blockedTargets = try c.decodeIfPresent([Target].self, forKey: .blockedTargets) ?? []
        allowedTargets = try c.decodeIfPresent([Target].self, forKey: .allowedTargets) ?? []
        targetNames = try c.decodeIfPresent([String: String].self, forKey: .targetNames) ?? [:]
        playMusic = try c.decodeIfPresent(Bool.self, forKey: .playMusic) ?? d.playMusic
        tracks = try c.decodeIfPresent([String].self, forKey: .tracks) ?? d.tracks
        requireCode = try c.decodeIfPresent(Bool.self, forKey: .requireCode) ?? d.requireCode
        rewardMinutes = try c.decodeIfPresent(Int.self, forKey: .rewardMinutes) ?? d.rewardMinutes
        pairingKey = try c.decodeIfPresent(String.self, forKey: .pairingKey) ?? ""
    }

    /// The first of `targets` that Lock In blocks, or nil if they're all fine.
    func blockedTarget(in targets: [Target]) -> Target? {
        if targets.contains(where: { allowedTargets.contains($0) }) { return nil }
        if targets.contains(where: { $0.kind == .app && Self.musicApps.contains($0.value) }) { return nil }
        return targets.first { blockedTargets.contains($0) }
            ?? targets.first { $0.kind == .category && blockedCategories.contains($0.value) }
    }

    func name(for target: Target) -> String { targetNames[target.id] ?? target.value }
}

/// A Lock In that is running or has just finished.
struct LockInSession: Codable, Equatable {
    var start: Date
    var end: Date
    /// Seconds of real (non-idle, not blocked) activity counted during the session.
    var activeSeconds: Double = 0

    var duration: Double { end.timeIntervalSince(start) }
    func remaining(at now: Date) -> Double { max(0, end.timeIntervalSince(now)) }
    /// A session only earns an unlock code if you were actually at the computer for most of it.
    var earnedCode: Bool { activeSeconds >= duration * 0.7 }
}

/// Six-digit codes the Mac shows for each finished Lock In. They change every 5 minutes, each one works for
/// 10 minutes, and the iPhone checks them offline with the same pairing key.
enum UnlockCode {
    static let period: TimeInterval = 5 * 60

    static func window(at date: Date) -> Int { Int(date.timeIntervalSince1970 / period) }

    /// When the code shown at `date` gets replaced.
    static func nextChange(after date: Date) -> Date {
        Date(timeIntervalSince1970: Double(window(at: date) + 1) * period)
    }

    static func code(key: String, day: String, index: Int, at date: Date) -> String {
        code(key: key, day: day, index: index, window: window(at: date))
    }

    private static func code(key: String, day: String, index: Int, window: Int) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(day)|\(index)|\(window)".utf8),
                                                  using: SymmetricKey(data: Data(normalizedKey(key).utf8)))
        let number = Array(mac).prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } % 1_000_000
        return String(format: "%06d", number)
    }

    /// Which of the day's Lock Ins a code belongs to, if it was shown within the last 10 minutes.
    static func index(of code: String, key: String, day: String, at date: Date, maxIndex: Int = 30) -> Int? {
        let digits = code.filter(\.isNumber)
        guard !key.isEmpty, digits.count == 6 else { return nil }
        let now = window(at: date)
        return (1...maxIndex).first { index in
            [now, now - 1].contains { self.code(key: key, day: day, index: index, window: $0) == digits }
        }
    }

    static func newKey() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let chars = (0..<8).map { _ in alphabet.randomElement()! }
        return String(chars[0..<4]) + "-" + String(chars[4..<8])
    }

    static func normalizedKey(_ raw: String) -> String {
        let chars = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard chars.count == 8 else { return raw.uppercased().trimmingCharacters(in: .whitespaces) }
        return String(chars.prefix(4)) + "-" + String(chars.suffix(4))
    }
}

enum Domains {
    /// "m.youtube.com" -> ["m.youtube.com", "youtube.com"], so a limit on youtube.com covers its subdomains.
    static func withParents(_ host: String) -> [String] {
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return [host] }
        return (0...(parts.count - 2)).map { parts[$0...].joined(separator: ".") }
    }
}
