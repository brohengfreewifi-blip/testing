import SwiftUI

/// Typing bar that sits above the iOS keyboard and forwards what you type to the game page:
/// into the focused text field if there is one, otherwise as key events on `document`.
struct KeyboardBar: View {
    @ObservedObject var session: GameSession
    @State private var text = ""
    @State private var synced = ""      // what the page already has, so we only send the difference
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Type here", text: $text)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.return)
                .onSubmit { send(special: "Enter"); session.hideKeyboard() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            barButton("escape", "Escape") { send(special: "Escape") }
            barButton("delete.left", "Backspace") {
                if text.isEmpty { session.keyboardSend(delete: 1, insert: "") } else { text.removeLast() }
            }
            barButton("return", "Enter") { send(special: "Enter") }
            barButton("xmark.circle.fill", "Close keyboard") { session.hideKeyboard() }
        }
        .padding(8)
        .background(.regularMaterial)
        .task(id: session.keyboardNonce) {
            let initial = await session.keyboardBegin()
            synced = initial
            text = initial
            try? await Task.sleep(nanoseconds: 150_000_000)   // a freshly inserted field ignores focus for a moment
            focused = true
        }
        .onChange(of: text) { _, new in
            let a = Array(synced), b = Array(new)
            var p = 0
            while p < a.count && p < b.count && a[p] == b[p] { p += 1 }
            synced = new
            session.keyboardSend(delete: a.count - p, insert: String(b[p...]))
        }
        // Losing focus (menu opened, user tapped the game) closes the bar; tapping another field reopens it.
        .onChange(of: focused) { _, f in if !f { session.hideKeyboard() } }
    }

    private func send(special: String) {
        session.keyboardSend(delete: 0, insert: "", special: special)
    }

    private func barButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22))
        }
        .accessibilityLabel(label)
    }
}
