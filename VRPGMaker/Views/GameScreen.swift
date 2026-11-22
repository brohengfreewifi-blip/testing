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

            if session.editingLayout || (session.padVisible && !session.controllerConnected) {
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
        .onChange(of: session.editingLayout) { _, editing in if editing { showMenu = false } }
        .onAppear { session.startControllers() }
        .onDisappear { session.stop() }
    }
}

// MARK: - On-screen pad (movable, resizable, custom buttons)

struct PadOverlay: View {
    @ObservedObject var session: GameSession
    @State private var selected: String?
    @State private var newKey = "C"

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            ZStack {
                ForEach(session.layout.elements) { el in
                    if (el.visible || session.editingLayout) && (el.kind != .cheat || session.game.engine == .mvmz) {
                        let p = el.pos(land)
                        Group {
                            if session.editingLayout {
                                editable(el, geo: geo.size, land: land)
                            } else {
                                control(el, interactive: true)
                            }
                        }
                        .opacity(el.visible ? session.layout.opacity : 0.3)
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                    }
                }
                if session.editingLayout {
                    editPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .coordinateSpace(name: "pad")
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func control(_ el: PadElement, interactive: Bool) -> some View {
        let size = CGFloat(el.size)
        switch el.kind {
        case .move:
            if session.layout.joystick {
                JoystickView(size: size) { if interactive { session.set($0, $1) } }
            } else {
                DPadView(size: size) { if interactive { session.set($0, $1) } }
            }
        case .action:
            HoldButton(label: el.label, size: size) { down in
                if interactive, let a = PadAction(rawValue: el.value) { session.set(a, down) }
            }
        case .key:
            HoldButton(label: el.label, size: size) { down in
                if interactive { session.sendKey(el.value, down) }
            }
        case .cheat:
            HoldButton(label: el.label, size: size) { down in
                if interactive && down { session.toggleCheat() }
            }
        }
    }

    // MARK: Edit mode

    @ViewBuilder
    private func editable(_ el: PadElement, geo: CGSize, land: Bool) -> some View {
        control(el, interactive: false)
            .allowsHitTesting(false)
            .frame(width: CGFloat(el.size), height: CGFloat(el.size))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected == el.id ? Color.yellow : Color.white.opacity(0.7),
                                  style: StrokeStyle(lineWidth: 2, dash: [5]))
            )
            .contentShape(Rectangle())
            .onTapGesture { selected = el.id }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("pad"))
                    .onChanged { v in
                        selected = el.id
                        guard let i = session.layout.elements.firstIndex(where: { $0.id == el.id }) else { return }
                        session.layout.elements[i].setPos(v.location.x / geo.width, v.location.y / geo.height, land: land)
                    }
            )
    }

    private var selectedIndex: Int? {
        session.layout.elements.firstIndex { $0.id == selected }
    }

    private var editPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Edit controls").font(.headline)
                    Spacer()
                    Button("Done") { selected = nil; session.editingLayout = false }
                        .buttonStyle(.borderedProminent)
                }
                Text("Drag a control to move it. Tap it to resize or edit.")
                    .font(.caption).foregroundStyle(.secondary)

                if let i = selectedIndex {
                    let el = session.layout.elements[i]
                    Divider()
                    Text("Selected: \(el.label)").font(.subheadline.bold())
                    HStack {
                        Text("Size")
                        Slider(value: Binding(
                            get: { session.layout.elements[i].size },
                            set: { session.layout.elements[i].size = $0 }), in: 36...240)
                    }
                    if el.kind != .move {
                        HStack {
                            Text("Label")
                            TextField("Label", text: Binding(
                                get: { session.layout.elements[i].label },
                                set: { session.layout.elements[i].label = String($0.prefix(6)) }))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    if el.kind == .key {
                        Picker("Sends key", selection: Binding(
                            get: { session.layout.elements[i].value },
                            set: { session.layout.elements[i].value = $0 })) {
                            ForEach(KeyChoice.all) { Text($0.name).tag($0.name) }
                        }
                    }
                    HStack {
                        Toggle("Visible", isOn: Binding(
                            get: { session.layout.elements[i].visible },
                            set: { session.layout.elements[i].visible = $0 }))
                        if el.kind == .key {
                            Button("Delete", role: .destructive) {
                                session.layout.elements.remove(at: i); selected = nil
                            }
                        }
                    }
                }

                Divider()
                Toggle("Joystick instead of D-pad", isOn: $session.layout.joystick)
                HStack {
                    Text("Opacity")
                    Slider(value: $session.layout.opacity, in: 0.2...1)
                }
                HStack {
                    Picker("New button key", selection: $newKey) {
                        ForEach(KeyChoice.all) { Text($0.name).tag($0.name) }
                    }
                    Button("Add button") {
                        let el = PadElement(id: UUID().uuidString, kind: .key, value: newKey, label: newKey,
                                            size: 56, visible: true, portrait: [0.5, 0.6], landscape: [0.5, 0.6])
                        session.layout.elements.append(el)
                        selected = el.id
                    }
                    .buttonStyle(.bordered)
                }
                Button("Reset layout", role: .destructive) { session.layout = .default; selected = nil }
            }
            .padding(14)
        }
        .frame(maxWidth: 440, maxHeight: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
        .padding(.horizontal, 60)
    }
}

// MARK: - Controls

struct HoldButton: View {
    let label: String
    let size: CGFloat
    let onChange: (Bool) -> Void
    @State private var down = false

    var body: some View {
        Circle()
            .fill(down ? Color.white.opacity(0.55) : Color.white.opacity(0.22))
            .frame(width: size, height: size)
            .overlay(
                Text(label)
                    .font(.system(size: max(11, size * 0.32), weight: .bold))
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .foregroundStyle(.white).padding(4)
            )
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; onChange(true) } }
                .onEnded { _ in down = false; onChange(false) })
    }
}

struct DPadView: View {
    let size: CGFloat
    let onChange: (PadAction, Bool) -> Void
    @State private var active = Set<PadAction>()

    var body: some View {
        let o = size * 0.35
        ZStack {
            Circle().fill(Color.white.opacity(0.2))
            Image(systemName: "arrowtriangle.up.fill").offset(y: -o)
            Image(systemName: "arrowtriangle.down.fill").offset(y: o)
            Image(systemName: "arrowtriangle.left.fill").offset(x: -o)
            Image(systemName: "arrowtriangle.right.fill").offset(x: o)
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - size / 2, dy = v.location.y - size / 2
                let t = size * 0.15
                var n = Set<PadAction>()
                if hypot(dx, dy) > size * 0.12 {
                    if dx > t { n.insert(.right) }
                    if dx < -t { n.insert(.left) }
                    if dy > t { n.insert(.down) }
                    if dy < -t { n.insert(.up) }
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

/// Analog-style stick: the knob follows the finger, and direction is sent as 8-way key presses.
struct JoystickView: View {
    let size: CGFloat
    let onChange: (PadAction, Bool) -> Void
    @State private var offset: CGSize = .zero
    @State private var active = Set<PadAction>()

    var body: some View {
        let r = size / 2
        let knob = size * 0.42
        ZStack {
            Circle().fill(Color.white.opacity(0.18))
            Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2)
            Circle().fill(Color.white.opacity(0.55)).frame(width: knob, height: knob).offset(offset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.location.x - r, dy = v.location.y - r
                let dist = hypot(dx, dy)
                let maxR = r - knob / 2
                let k: CGFloat = dist > maxR ? maxR / dist : 1
                offset = CGSize(width: dx * k, height: dy * k)
                let t = r * 0.3
                var n = Set<PadAction>()
                if dist > t * 0.8 {
                    if dx > t { n.insert(.right) }
                    if dx < -t { n.insert(.left) }
                    if dy > t { n.insert(.down) }
                    if dy < -t { n.insert(.up) }
                }
                apply(n)
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.1)) { offset = .zero }
                apply([])
            })
    }

    private func apply(_ n: Set<PadAction>) {
        for a in active.subtracting(n) { onChange(a, false) }
        for a in n.subtracting(active) { onChange(a, true) }
        active = n
    }
}
