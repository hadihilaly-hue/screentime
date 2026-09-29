import SwiftUI

/// Ending Lock In or turning off "Earn your apps" early takes typing a sentence, not one tap.
struct GiveUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    var title = "Give up this Lock In?"
    var detail = "You won't earn phone minutes. To end it anyway, type:"
    var action = "Give up"
    let onGiveUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(detail)
            Text(LockInSettings.giveUpPhrase).font(.headline)
            TextField("Type it here", text: $typed)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            HStack {
                Spacer()
                Button("Keep working") { dismiss() }.keyboardShortcut(.defaultAction)
                Button(action, role: .destructive) {
                    onGiveUp()
                    dismiss()
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).lowercased() != LockInSettings.giveUpPhrase.lowercased())
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 420)
        #endif
    }
}
