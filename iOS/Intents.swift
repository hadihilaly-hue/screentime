import AppIntents

struct LogAppOpenedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log App Opened"
    static var description = IntentDescription(
        "Tells Screentime an app was opened. Returns true if the app is over its limit or blocked right now.")

    @Parameter(title: "App name", description: "Exactly as you want it to appear, e.g. Instagram")
    var appName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log that \(\.$appName) opened")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: PhoneState.shared.appOpened(appName))
    }
}

struct LogAppClosedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log App Closed"
    static var description = IntentDescription("Tells Screentime you left the app you were using.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PhoneState.shared.appClosed()
        return .result()
    }
}
