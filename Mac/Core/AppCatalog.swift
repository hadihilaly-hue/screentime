import AppKit

/// Looks up names, icons and categories for installed Mac apps.
@MainActor
final class AppCatalog {
    private var categoryCache: [String: String] = [:]
    private var iconCache: [String: NSImage] = [:]

    private static let knownApps: [String: String] = [
        "com.apple.MobileSMS": "Communication", "com.apple.mail": "Communication",
        "com.apple.FaceTime": "Communication", "com.tinyspeck.slackmacgap": "Communication",
        "com.hnc.Discord": "Communication", "net.whatsapp.WhatsApp": "Communication",
        "com.microsoft.teams2": "Communication", "us.zoom.xos": "Communication",
        "com.apple.Music": "Entertainment", "com.spotify.client": "Entertainment",
        "com.apple.TV": "Entertainment", "com.apple.podcasts": "Entertainment",
        "com.apple.dt.Xcode": "Productivity", "com.microsoft.VSCode": "Productivity",
        "com.apple.Terminal": "Productivity", "com.googlecode.iterm2": "Productivity",
        "com.apple.iWork.Pages": "Productivity", "com.apple.iWork.Keynote": "Productivity",
        "com.apple.iWork.Numbers": "Productivity", "com.apple.Notes": "Productivity",
        "notion.id": "Productivity", "com.microsoft.Word": "Productivity",
        "com.microsoft.Excel": "Productivity", "com.microsoft.Powerpoint": "Productivity",
        "com.apple.finder": "Utilities", "com.apple.systempreferences": "Utilities",
        "com.apple.Safari": "Utilities", "com.google.Chrome": "Utilities",
        "company.thebrowser.Browser": "Utilities", "com.brave.Browser": "Utilities",
        "com.microsoft.edgemac": "Utilities", "org.mozilla.firefox": "Utilities",
        "com.roblox.RobloxPlayer": "Games", "com.valvesoftware.steam": "Games",
        "com.mojang.minecraftlauncher": "Games",
    ]

    func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if let url = url(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[bundleID] = image
        return image
    }

    func category(for bundleID: String, overrides: [String: String]) -> String {
        if let override = overrides["app:\(bundleID)"] { return override }
        if let cached = categoryCache[bundleID] { return cached }
        let category = Self.knownApps[bundleID] ?? lsCategory(for: bundleID) ?? "Other"
        categoryCache[bundleID] = category
        return category
    }

    private func lsCategory(for bundleID: String) -> String? {
        guard let url = url(for: bundleID),
              let type = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String
        else { return nil }
        let t = type.replacingOccurrences(of: "public.app-category.", with: "")
        if t.contains("games") { return "Games" }
        switch t {
        case "social-networking": return "Social"
        case "entertainment", "video", "music": return "Entertainment"
        case "productivity", "business", "developer-tools", "finance": return "Productivity"
        case "education", "reference": return "Education"
        case "news", "magazines", "sports": return "News"
        case "photography", "graphics-design": return "Creativity"
        case "utilities": return "Utilities"
        default: return nil
        }
    }
}
