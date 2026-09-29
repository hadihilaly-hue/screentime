# Screentime

A personal screen time tracker and limiter for **Mac** and **iPhone**. Everything stays on your devices as local JSON files. There are no accounts and no servers.

## What it does

| | Mac | iPhone |
|---|---|---|
| Time per app | yes, automatic | yes, through Shortcuts automations |
| Time per website | yes (Safari, Chrome, Arc, Brave, Edge, Vivaldi, Opera) | — |
| Categories (Social, Games, …) | yes, auto-detected and editable | yes, auto-detected and editable |
| Daily limits per app, website or category | yes, full-screen "Time's up" overlay | yes, full-screen "Time's up" screen plus notifications |
| Focus schedules (homework, bedtime) | yes | yes |
| Warnings before a limit, "N more minutes" snooze | yes | yes |
| Daily distraction goal (only Social, Entertainment, Games count, so homework doesn't), hourly and weekly charts, pickups | yes | yes |
| Personal notes and a motto on block screens | yes | yes |
| Lock In: timed focus that blocks distractions, loops focus music | yes (Spotify on repeat) | yes (opens Spotify) |
| Earn your apps: phone apps stay locked until you enter a code from a finished Mac Lock In | issues codes | checks codes |

## Requirements

- A Mac with **Xcode 15 or newer** (free from the App Store).
- macOS 13 or newer and iOS 17 or newer.
- For the iPhone, a **free Apple ID** is enough. No paid developer account is needed.

## Run the Mac app

1. Open `Screentime.xcodeproj` in Xcode.
2. In the toolbar's scheme menu, pick **ScreentimeMac** → **My Mac**, then press **▶ Run**.
3. An hourglass and today's time appear in the menu bar. Click it and choose **Open Dashboard**.
4. Allow notifications when asked. The first time you use each browser, macOS asks: *"Screentime wants to control Safari/Chrome"*. Click **OK**. That lets it read the current tab's website.
5. To keep it installed: in Xcode, choose **Product → Archive → Distribute App → Copy App**, move `Screentime.app` into `/Applications`, and turn on **Settings → Open Screentime at login** inside the app.

## Install on your iPhone (free Apple ID)

1. In Xcode, go to **Xcode → Settings → Accounts → +**, choose **Apple ID** and sign in.
2. Plug in your iPhone with a cable and tap **Trust** on the phone.
3. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it **on**, and let the phone restart.
4. In Xcode, select the **ScreentimePhone** target → **Signing & Capabilities** → **Team** → pick *Your Name (Personal Team)*.
   - If Xcode says the bundle identifier is taken, change `com.hadihilaly.screentime.phone` to something unique, e.g. `com.yourname.screentime`.
5. Pick your iPhone in the scheme's device menu and press **▶ Run**.
6. The first launch says "Untrusted Developer". On the iPhone, open **Settings → General → VPN & Device Management**, tap your Apple ID, then tap **Trust**. Open Screentime again.
7. Open the **Setup** tab in the app and follow the steps there to create the Shortcuts automations.

**Every 7 days:** apps installed with a free Apple ID stop launching after 7 days. Plug the phone in and press **▶ Run** again. Your data is kept.

### How iPhone tracking works

Apple only lets apps read real Screen Time data through the Family Controls entitlement, and that requires a paid developer account. Screentime uses Shortcuts instead:

- **"When Instagram is opened"** runs `Log App Opened (Instagram)`. That action returns `true` if Instagram is over its limit or inside a focus schedule, and the automation then opens Screentime's *Time's Up* screen.
- **"When Instagram is closed"** runs `Log App Closed (Instagram)`. Each app gets its own close automation. When you jump straight from one app to another, the first app's close event can arrive after the second app's open event, and the app name lets Screentime ignore that late event.

The time between those two events counts as usage. Each visit is capped (45 min by default, adjustable) in case a "closed" event is missed. While you're in an app, Screentime schedules a notification for the moment its limit runs out.

## Lock In and "Earn your apps"

- **Lock In** (Mac menu bar or Dashboard → Lock In; iPhone Focus tab) blocks the categories you pick (Social, Entertainment and Games by default) plus any extra apps or sites until the timer runs out. It can't be snoozed, quitting Screentime doesn't end it, and giving up early means typing a sentence. On the Mac it loops *Experience* (Ludovico Einaudi) and *Solas* (Jamie Duffy) in the Spotify app; change the songs by pasting Spotify song links.
- A Mac Lock In counts as finished only if you were active on non-blocked apps for at least 70% of it. Each finished one shows a **6-digit unlock code** on Dashboard → Lock In. The code changes every 5 minutes, each one works for 10 minutes, and each Lock In's code works once.
- On the iPhone, turn on **Focus → Earn your apps** and type the Mac's pairing key (shown under the codes). From then on, opening a locked app (through its Shortcuts automation) shows *Earn it first* until you type a current code. A code unlocks those apps for 20 minutes.
- Codes are checked offline with an HMAC of the pairing key, the day and the 5-minute window, so there's no server and the two devices never talk to each other. Both clocks need to be set automatically.

## Project layout

```
project.yml          XcodeGen spec (regenerate with `xcodegen generate`)
Shared/              Models, categories, JSON storage (both apps)
Mac/Core/            Tracker, browser tab reader, limit enforcer, block overlay
Mac/Views/           Menu bar and dashboard (Today, Week, Limits, Focus, Settings)
iOS/                 App state, Shortcuts App Intents, SwiftUI screens
```

Data lives in `~/Library/Application Support/Screentime/` on the Mac and inside the app's container on the iPhone. Each day is saved as `usage/YYYY-MM-DD.json`, and your settings are in `config.json`.
