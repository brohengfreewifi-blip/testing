import SwiftUI

struct GameScreen: View {
    @StateObject private var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false

    init(game: Game) { _session = StateObject(wrappedValue: GameSession(game: game)) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WebGameView(session: session).ignoresSafeArea()

            if session.padVisible && !session.controllerConnected {
                PadOverlay(session: session)
            }

            // Same control, same corner, on every engine.
            VStack {
                HStack {
                    Spacer()
                    Button { showMenu = true } label: {
                        Image(systemName: "line.3.horizontal.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.65))
                            .shadow(radius: 3)
                    }
                }
                Spacer()
            }
            .padding(12)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showMenu) {
            GameMenu(session: session) { showMenu = false; dismiss() }
                .presentationDetents([.medium, .large])
        }
        .onAppear { session.startControllers() }
        .onDisappear { session.stop() }
    }
}

// MARK: - On-screen gamepad

struct PadOverlay: View {
    let session: GameSession

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                DPadView { session.set($0, $1) }
                Spacer()
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        HoldButton(label: "Menu", size: 44) { session.set(.menu, $0) }
                        HoldButton(label: "Dash", size: 44) { session.set(.shift, $0) }
                    }
                    HStack(spacing: 14) {
                        HoldButton(label: "B", size: 66) { session.set(.cancel, $0) }
                        HoldButton(label: "A", size: 66) { session.set(.ok, $0) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .opacity(0.65)
    }
}

struct HoldButton: View {
    let label: String
    let size: CGFloat
    let onChange: (Bool) -> Void
    @State private var down = false

    var body: some View {
        Circle()
            .fill(down ? Color.white.opacity(0.55) : Color.white.opacity(0.22))
            .frame(width: size, height: size)
            .overlay(Text(label).font(.system(size: size > 50 ? 22 : 12, weight: .bold)).foregroundStyle(.white))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; onChange(true) } }
                .onEnded { _ in down = false; onChange(false) })
    }
}

struct DPadView: View {
    let onChange: (PadAction, Bool) -> Void
    @State private var active = Set<PadAction>()
    private let size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.2))
            Image(systemName: "arrowtriangle.up.fill").offset(y: -52)
            Image(systemName: "arrowtriangle.down.fill").offset(y: 52)
            Image(systemName: "arrowtriangle.left.fill").offset(x: -52)
            Image(systemName: "arrowtriangle.right.fill").offset(x: 52)
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - size / 2, dy = v.location.y - size / 2
                var n = Set<PadAction>()
                if hypot(dx, dy) > 18 {
                    if dx > 22 { n.insert(.right) }
                    if dx < -22 { n.insert(.left) }
                    if dy > 22 { n.insert(.down) }
                    if dy < -22 { n.insert(.up) }
                }
                apply(n)
            }
            .onEnded { _ in apply([]) })
    }

    private func apply(_ n: Set<PadAction>) {
        for a in active.subtracting(n) { onChange(a, false) }
        for a in n.subtracting(active) { onChange(a, true) }
        active = n
    }
}
