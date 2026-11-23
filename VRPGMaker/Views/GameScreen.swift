import SwiftUI
import UIKit

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
                    VStack(spacing: 10) {
                        Button { showMenu = true } label: {
                            Image(systemName: "line.3.horizontal.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.65))
                                .shadow(radius: 3)
                        }
                        // Hide / show the on-screen controls. Not needed while a controller is
                        // connected (the pad is already hidden) or while editing the layout.
                        if !session.controllerConnected && !session.editingLayout {
                            Button { session.padVisible.toggle() } label: {
                                Image(systemName: session.padVisible ? "eye.slash.circle.fill" : "eye.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .shadow(radius: 3)
                            }
                            .accessibilityLabel(session.padVisible ? "Hide controls" : "Show controls")
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
        }
        .alert("Cheat UI", isPresented: Binding(
            get: { session.cheatError != nil },
            set: { if !$0 { session.cheatError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(session.cheatError ?? "") }
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
    @State private var tab: EditTab = .control
    @State private var panelAtTop = true
    @State private var panelCollapsed = false
    @State private var newKind: NewKind = .key
    @State private var newKey = "C"
    @State private var newAction: PadAction = .pageUp
    @State private var pinchBase: [String: Double] = [:]

    enum EditTab: String, CaseIterable, Identifiable {
        case control = "Control", layout = "Layout"
        var id: String { rawValue }
    }
    enum NewKind: String, CaseIterable, Identifiable {
        case key = "Key", action = "Action"
        var id: String { rawValue }
    }

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
                        .opacity(el.visible ? session.layout.opacity * el.opacity : 0.3)
                        .position(x: geo.size.width * p.x, y: geo.size.height * p.y)
                    }
                }
                if session.editingLayout {
                    editPanel(land: land)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAtTop ? .top : .bottom)
                }
            }
            .coordinateSpace(name: "pad")
        }
        // Hiding the pad (or plugging in a controller) must not leave a sticky button held down.
        .onDisappear { session.releaseAll() }
    }

    // MARK: Controls

    @ViewBuilder
    private func control(_ el: PadElement, interactive: Bool) -> some View {
        let size = CGFloat(el.size)
        let haptics = session.layout.haptics
        switch el.kind {
        case .move:
            if session.layout.joystick {
                JoystickView(size: size) { if interactive { session.set($0, $1) } }
            } else {
                DPadView(size: size) { if interactive { session.set($0, $1) } }
            }
        case .action:
            HoldButton(label: el.label, size: size, latch: el.latch, haptics: haptics) { down in
                if interactive, let a = PadAction(rawValue: el.value) { session.set(a, down) }
            }
        case .key:
            HoldButton(label: el.label, size: size, latch: el.latch, haptics: haptics) { down in
                if interactive { session.sendKey(el.value, down) }
            }
        case .cheat:
            HoldButton(label: el.label, size: size, haptics: haptics) { down in
                if interactive && down { session.toggleCheat() }
            }
        }
    }

    // MARK: Edit mode

    private func index(of id: String) -> Int? {
        session.layout.elements.firstIndex { $0.id == id }
    }

    private var selectedIndex: Int? {
        selected.flatMap { index(of: $0) }
    }

    private func snapped(_ v: Double) -> Double {
        guard session.layout.snap else { return v }
        return (v / PadLayout.snapStep).rounded() * PadLayout.snapStep
    }

    private func clampSize(_ v: Double) -> Double {
        min(max(v, PadLayout.sizeRange.lowerBound), PadLayout.sizeRange.upperBound)
    }

    /// Two-way binding to one property of one element, looked up by id so deleting it can never crash.
    private func binding<T>(_ id: String, _ kp: WritableKeyPath<PadElement, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { session.layout.elements.first { $0.id == id }?[keyPath: kp] ?? fallback },
            set: { v in
                if let i = index(of: id) { session.layout.elements[i][keyPath: kp] = v }
            })
    }

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
            .onTapGesture { selected = el.id; tab = .control }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("pad"))
                    .onChanged { v in
                        selected = el.id
                        guard let i = index(of: el.id) else { return }
                        session.layout.elements[i].setPos(snapped(v.location.x / geo.width),
                                                          snapped(v.location.y / geo.height), land: land)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        guard let i = index(of: el.id) else { return }
                        selected = el.id
                        let base = pinchBase[el.id] ?? session.layout.elements[i].size
                        pinchBase[el.id] = base
                        session.layout.elements[i].size = clampSize(base * Double(v.magnification))
                    }
                    .onEnded { _ in pinchBase[el.id] = nil }
            )
    }

    private func editPanel(land: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text("Edit controls").font(.headline)
                Spacer()
                Button { panelAtTop.toggle() } label: {
                    Image(systemName: panelAtTop ? "arrow.down.to.line" : "arrow.up.to.line")
                }
                .accessibilityLabel(panelAtTop ? "Move panel to bottom" : "Move panel to top")
                Button { panelCollapsed.toggle() } label: {
                    Image(systemName: panelCollapsed ? "chevron.down" : "chevron.up")
                }
                .accessibilityLabel(panelCollapsed ? "Expand panel" : "Collapse panel")
                Button("Done") { selected = nil; session.editingLayout = false }
                    .buttonStyle(.borderedProminent)
            }
            if !panelCollapsed {
                Picker("Section", selection: $tab) {
                    ForEach(EditTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if tab == .control { controlTab(land: land) } else { layoutTab }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: land ? 130 : 230)
            }
        }
        .padding(12)
        .frame(maxWidth: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 60)
        .padding(.vertical, 8)
    }

    // MARK: Control tab (the selected control)

    @ViewBuilder
    private func controlTab(land: Bool) -> some View {
        if let i = selectedIndex {
            let el = session.layout.elements[i]
            Text("Selected: \(el.label.isEmpty ? el.kind.rawValue : el.label)").font(.subheadline.bold())
            HStack {
                Text("Size")
                Slider(value: binding(el.id, \.size, fallback: el.size), in: PadLayout.sizeRange)
                Text("\(Int(el.size))").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
            HStack {
                Text("Opacity")
                Slider(value: binding(el.id, \.opacity, fallback: 1), in: 0.2...1)
            }
            if el.kind != .move {
                HStack {
                    Text("Label")
                    TextField("Label", text: Binding(
                        get: { el.label },
                        set: { v in
                            if let j = index(of: el.id) { session.layout.elements[j].label = String(v.prefix(6)) }
                        }))
                        .textFieldStyle(.roundedBorder)
                }
            }
            if el.kind == .key {
                Picker("Sends key", selection: binding(el.id, \.value, fallback: el.value)) {
                    ForEach(KeyChoice.all) { Text($0.name).tag($0.name) }
                }
            }
            if el.kind == .key || el.kind == .action {
                Toggle("Sticky: tap to hold, tap again to release",
                       isOn: binding(el.id, \.latch, fallback: false))
            }
            Toggle("Visible", isOn: binding(el.id, \.visible, fallback: true))
            HStack {
                Text("Nudge")
                Spacer()
                nudgeButton("arrow.left", el.id, -1, 0, land)
                nudgeButton("arrow.up", el.id, 0, -1, land)
                nudgeButton("arrow.down", el.id, 0, 1, land)
                nudgeButton("arrow.right", el.id, 1, 0, land)
            }
            HStack {
                if el.kind == .key || el.kind == .action {
                    Button("Duplicate") { duplicate(i) }.buttonStyle(.bordered)
                }
                if el.isCustom {
                    Button("Delete", role: .destructive) {
                        session.layout.elements.remove(at: i); selected = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            Text("Tap a control to select it. Drag to move it, pinch to resize.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nudgeButton(_ icon: String, _ id: String, _ dx: Double, _ dy: Double, _ land: Bool) -> some View {
        Button {
            guard let i = index(of: id) else { return }
            let p = session.layout.elements[i].pos(land)
            let step = 0.005
            session.layout.elements[i].setPos(Double(p.x) + dx * step, Double(p.y) + dy * step, land: land)
        } label: { Image(systemName: icon).frame(width: 22) }
        .buttonStyle(.bordered)
    }

    private func duplicate(_ i: Int) {
        var copy = session.layout.elements[i]
        copy.id = UUID().uuidString
        copy.portrait = copy.portrait.map { min($0 + 0.05, 0.96) }
        copy.landscape = copy.landscape.map { min($0 + 0.05, 0.96) }
        session.layout.elements.append(copy)
        selected = copy.id
    }

    // MARK: Layout tab (everything that applies to the whole pad)

    @ViewBuilder
    private var layoutTab: some View {
        Group {
            Toggle("Joystick instead of D-pad", isOn: $session.layout.joystick)
            HStack {
                Text("Opacity")
                Slider(value: $session.layout.opacity, in: 0.2...1)
            }
            Toggle("Snap to grid while dragging", isOn: $session.layout.snap)
            Toggle("Vibrate on press", isOn: $session.layout.haptics)
        }
        Group {
            Text("Quick layouts").font(.subheadline.bold())
            HStack {
                Button("Mirror left/right") { session.layout.mirrorHorizontally() }
                Button("Smaller") { session.layout.scaleSizes(by: 0.85) }
                Button("Larger") { session.layout.scaleSizes(by: 1.18) }
            }
            .buttonStyle(.bordered)
        }
        Group {
            Divider()
            Text("Add a button").font(.subheadline.bold())
            Picker("Type", selection: $newKind) {
                ForEach(NewKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if newKind == .key {
                Picker("Key", selection: $newKey) {
                    ForEach(KeyChoice.all) { Text($0.name).tag($0.name) }
                }
            } else {
                Picker("Action", selection: $newAction) {
                    ForEach(PadAction.allCases) { Text($0.title).tag($0) }
                }
            }
            Button("Add button") { addButton() }.buttonStyle(.bordered)
        }
        Group {
            Divider()
            Button("Reset layout", role: .destructive) { session.layout = .default; selected = nil }
        }
    }

    private func addButton() {
        let el: PadElement
        switch newKind {
        case .key:
            el = PadElement(id: UUID().uuidString, kind: .key, value: newKey, label: String(newKey.prefix(6)),
                            size: 56, visible: true, portrait: [0.5, 0.6], landscape: [0.5, 0.6])
        case .action:
            el = PadElement(id: UUID().uuidString, kind: .action, value: newAction.rawValue, label: newAction.shortLabel,
                            size: 56, visible: true, portrait: [0.5, 0.6], landscape: [0.5, 0.6])
        }
        session.layout.elements.append(el)
        selected = el.id
        tab = .control
    }
}

// MARK: - Controls

struct HoldButton: View {
    let label: String
    let size: CGFloat
    var latch = false
    var haptics = true
    let onChange: (Bool) -> Void
    @State private var down = false
    @State private var pressing = false

    var body: some View {
        Circle()
            .fill(down ? Color.white.opacity(0.55) : Color.white.opacity(0.22))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.yellow.opacity(latch && down ? 0.9 : 0), lineWidth: 2))
            .overlay(
                Text(label)
                    .font(.system(size: max(11, size * 0.32), weight: .bold))
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .foregroundStyle(.white).padding(4)
            )
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true
                    buzz()
                    if latch { down.toggle(); onChange(down) } else { down = true; onChange(true) }
                }
                .onEnded { _ in
                    pressing = false
                    if !latch { down = false; onChange(false) }
                })
    }

    private func buzz() {
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
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
