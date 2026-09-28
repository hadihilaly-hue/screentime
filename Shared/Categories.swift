import Foundation

enum Categories {
    static let all = [
        "Social", "Entertainment", "Games", "Communication", "Productivity",
        "Education", "News", "Shopping", "Creativity", "Utilities", "Other",
    ]

    static let icons: [String: String] = [
        "Social": "person.2.fill",
        "Entertainment": "play.tv.fill",
        "Games": "gamecontroller.fill",
        "Communication": "message.fill",
        "Productivity": "hammer.fill",
        "Education": "graduationcap.fill",
        "News": "newspaper.fill",
        "Shopping": "cart.fill",
        "Creativity": "paintbrush.fill",
        "Utilities": "wrench.and.screwdriver.fill",
        "Other": "square.grid.2x2.fill",
    ]

    static func icon(for category: String) -> String { icons[category] ?? "square.grid.2x2.fill" }

    private static let sites: [String: String] = [
        "youtube.com": "Entertainment", "netflix.com": "Entertainment", "twitch.tv": "Entertainment",
        "hulu.com": "Entertainment", "disneyplus.com": "Entertainment", "max.com": "Entertainment",
        "primevideo.com": "Entertainment", "spotify.com": "Entertainment", "crunchyroll.com": "Entertainment",
        "instagram.com": "Social", "tiktok.com": "Social", "twitter.com": "Social", "x.com": "Social",
        "facebook.com": "Social", "reddit.com": "Social", "snapchat.com": "Social", "pinterest.com": "Social",
        "threads.net": "Social", "tumblr.com": "Social", "linkedin.com": "Social", "bsky.app": "Social",
        "discord.com": "Communication", "mail.google.com": "Communication", "outlook.live.com": "Communication",
        "web.whatsapp.com": "Communication", "messenger.com": "Communication", "slack.com": "Communication",
        "docs.google.com": "Productivity", "drive.google.com": "Productivity", "notion.so": "Productivity",
        "github.com": "Productivity", "calendar.google.com": "Productivity", "figma.com": "Creativity",
        "chatgpt.com": "Productivity", "claude.ai": "Productivity", "canva.com": "Creativity",
        "classroom.google.com": "Education", "khanacademy.org": "Education", "quizlet.com": "Education",
        "wikipedia.org": "Education", "coursera.org": "Education", "desmos.com": "Education",
        "canvas.instructure.com": "Education", "schoology.com": "Education", "duolingo.com": "Education",
        "nytimes.com": "News", "cnn.com": "News", "bbc.com": "News", "theguardian.com": "News",
        "news.google.com": "News", "espn.com": "News", "news.ycombinator.com": "News",
        "amazon.com": "Shopping", "ebay.com": "Shopping", "etsy.com": "Shopping", "target.com": "Shopping",
        "chess.com": "Games", "lichess.org": "Games", "roblox.com": "Games", "poki.com": "Games",
        "coolmathgames.com": "Games",
    ]

    static func forSite(_ domain: String) -> String? {
        var host = domain
        while true {
            if let hit = sites[host] { return hit }
            guard let dot = host.firstIndex(of: ".") else { return nil }
            host = String(host[host.index(after: dot)...])
            if !host.contains(".") { return nil }
        }
    }

    private static let appNames: [String: String] = [
        "instagram": "Social", "tiktok": "Social", "snapchat": "Social", "x": "Social", "twitter": "Social",
        "facebook": "Social", "reddit": "Social", "threads": "Social", "pinterest": "Social", "bereal": "Social",
        "linkedin": "Social", "tumblr": "Social", "bluesky": "Social",
        "youtube": "Entertainment", "netflix": "Entertainment", "twitch": "Entertainment", "spotify": "Entertainment",
        "hulu": "Entertainment", "disney+": "Entertainment", "max": "Entertainment", "prime video": "Entertainment",
        "tv": "Entertainment", "music": "Entertainment", "podcasts": "Entertainment", "crunchyroll": "Entertainment",
        "messages": "Communication", "whatsapp": "Communication", "discord": "Communication", "mail": "Communication",
        "gmail": "Communication", "facetime": "Communication", "slack": "Communication", "messenger": "Communication",
        "telegram": "Communication", "signal": "Communication", "phone": "Communication",
        "roblox": "Games", "minecraft": "Games", "clash royale": "Games", "clash of clans": "Games",
        "brawl stars": "Games", "fortnite": "Games", "chess": "Games", "candy crush": "Games", "pokémon go": "Games",
        "notes": "Productivity", "notion": "Productivity", "google docs": "Productivity", "calendar": "Productivity",
        "reminders": "Productivity", "chatgpt": "Productivity", "claude": "Productivity", "files": "Productivity",
        "duolingo": "Education", "quizlet": "Education", "khan academy": "Education", "google classroom": "Education",
        "canvas": "Education", "schoology": "Education", "books": "Education",
        "news": "News", "espn": "News", "the new york times": "News",
        "amazon": "Shopping", "shein": "Shopping", "temu": "Shopping", "depop": "Shopping",
        "camera": "Creativity", "photos": "Creativity", "capcut": "Creativity", "vsco": "Creativity",
        "safari": "Utilities", "chrome": "Utilities", "maps": "Utilities", "settings": "Utilities",
    ]

    static func forAppName(_ name: String) -> String? {
        appNames[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}
