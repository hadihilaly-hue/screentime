import CoreGraphics
import IOKit.pwr_mgt

enum SystemActivity {
    /// Seconds since the last keyboard, mouse or trackpad event.
    static func idleSeconds() -> Double {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// True while something (usually video playback) is keeping the display awake.
    static func isMediaPlaying() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int]
        else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }
}
