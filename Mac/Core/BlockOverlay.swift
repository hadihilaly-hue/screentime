import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen "time's up" cover shown on every display.
@MainActor
final class BlockOverlayController {
    private var windows: [NSWindow] = []

    var isVisible: Bool { !windows.isEmpty }

    func show(_ reason: BlockReason, motto: String, snoozeMinutes: Int,
              onLeave: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        dismiss()
        let main = NSScreen.main
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            let view = BlockView(reason: reason, motto: motto, snoozeMinutes: snoozeMinutes,
                                 showsControls: screen == main, onLeave: onLeave, onSnooze: onSnooze)
            panel.contentView = NSHostingView(rootView: view)
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            windows.append(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        (windows.first { $0.screen == main } ?? windows.first)?.makeKey()
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private struct BlockView: View {
    let reason: BlockReason
    let motto: String
    let snoozeMinutes: Int
    let showsControls: Bool
    let onLeave: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            if showsControls {
                VStack(spacing: 22) {
                    Image(systemName: reason.canSnooze ? "hourglass" : "moon.stars.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(reason.title)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(reason.detail)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                    if !reason.note.isEmpty {
                        Text("“\(reason.note)”")
                            .font(.title2.italic())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                            .padding(.top, 8)
                    }
                    if !motto.isEmpty {
                        Text(motto)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    HStack(spacing: 14) {
                        Button(action: onLeave) {
                            Text(leaveTitle).frame(minWidth: 180)
                        }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        if reason.canSnooze {
                            Button(action: onSnooze) {
                                Text("\(snoozeMinutes) more minutes").frame(minWidth: 140)
                            }
                            .controlSize(.large)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 16)
                }
                .foregroundStyle(.white)
                .padding(40)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var leaveTitle: String {
        if reason.activity.site != nil, reason.target.kind != .app { return "Close this tab" }
        return "Leave \(reason.activity.appName)"
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
