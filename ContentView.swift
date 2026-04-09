// Vibed/ContentView.swift

import SwiftUI

// MARK: - ContentView

struct ContentView: View {

    @StateObject private var store = VibeStore()

    // ── Feed state ─────────────────────────────────────────────────────────────
    @State private var currentIndex  = 0
    @State private var isInteractive = false   // double-tap → full-screen mode

    // ── Vertical browsing ──────────────────────────────────────────────────────
    @State private var dragY: CGFloat = 0
    @State private var isBrowsing    = false

    // ── Horizontal nav (feed ↔ account) ───────────────────────────────────────
    // 0 = feed visible   -width = account visible
    @State private var horizontalOffset: CGFloat = 0

    // ── Gesture axis lock ──────────────────────────────────────────────────────
    @State private var lockedAxis: Axis? = nil

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // ── Account panel ──────────────────────────────────────────────
                AccountView()
                    .environmentObject(store)
                    .offset(x: horizontalOffset + geo.size.width)
                    // Swipe right to close account
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { v in
                                let dx = v.translation.width
                                if dx > 0 {
                                    horizontalOffset = max(-geo.size.width, min(0, -geo.size.width + dx))
                                }
                            }
                            .onEnded { v in
                                let threshold = geo.size.width * 0.3
                                let fast = v.velocity.width > 500
                                withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
                                    horizontalOffset = (v.translation.width > threshold || fast) ? 0 : -geo.size.width
                                }
                            }
                    )

                // ── Feed panel ─────────────────────────────────────────────────
                ZStack {
                    vibeStack(size: geo.size)

                    if !isInteractive {
                        // Transparent layer that owns gestures in view mode
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(browseAndAccountGesture(geo: geo))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isInteractive = true
                                }
                            }

                        viewModeFooter(
                            vibe: store.vibes[currentIndex],
                            safeBottom: geo.safeAreaInsets.bottom
                        )
                        .allowsHitTesting(false)
                    }

                    // Back button — bottom-left, white 60% opacity
                    if isInteractive {
                        VStack {
                            Spacer()
                            HStack {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isInteractive = false
                                    }
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 44, height: 44)
                                        .background(.white.opacity(0.15), in: Circle())
                                }
                                Spacer()
                            }
                            .padding(.leading, 22)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 22)
                        }
                        .transition(.opacity)
                    }
                }
                .offset(x: horizontalOffset)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: isInteractive)
    }

    // MARK: - Vibe stack

    @ViewBuilder
    private func vibeStack(size: CGSize) -> some View {
        // Previous
        if currentIndex > 0 {
            VibeRenderer(vibe: store.vibes[currentIndex - 1], isInteractive: false)
                .ignoresSafeArea()
                .offset(y: -size.height + dragY)
        }

        // Current
        VibeRenderer(vibe: store.vibes[currentIndex], isInteractive: isInteractive)
            .ignoresSafeArea()
            .offset(y: dragY)

        // Next
        if currentIndex < store.vibes.count - 1 {
            VibeRenderer(vibe: store.vibes[currentIndex + 1], isInteractive: false)
                .ignoresSafeArea()
                .offset(y: size.height + dragY)
        }
    }

    // MARK: - Gestures

    private func browseAndAccountGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { v in
                if lockedAxis == nil {
                    let ax = abs(v.translation.width)
                    let ay = abs(v.translation.height)
                    guard ax > 15 || ay > 15 else { return }
                    lockedAxis = ax > ay * 1.4 ? .horizontal : .vertical
                }

                switch lockedAxis {
                case .horizontal:
                    // Only left swipe opens account
                    let dx = v.translation.width
                    if dx < 0 {
                        horizontalOffset = max(-geo.size.width, dx)
                    }
                case .vertical:
                    handleVerticalDrag(dy: v.translation.height, height: geo.size.height)
                case nil:
                    break
                }
            }
            .onEnded { v in
                defer { lockedAxis = nil }
                switch lockedAxis {
                case .horizontal:
                    commitHorizontal(velocity: v.velocity.width, width: geo.size.width)
                case .vertical:
                    commitVertical(velocity: v.velocity.height, height: geo.size.height)
                case nil:
                    snapBackVertical()
                }
            }
    }

    // MARK: Horizontal

    private func commitHorizontal(velocity: CGFloat, width: CGFloat) {
        let moved = abs(horizontalOffset)
        let open  = moved > width * 0.3 || velocity < -500
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            horizontalOffset = open ? -width : 0
        }
    }

    // MARK: Vertical

    private func handleVerticalDrag(dy: CGFloat, height: CGFloat) {
        guard !isBrowsing else { return }
        if dy < 0, currentIndex < store.vibes.count - 1 {
            dragY = dy
        } else if dy > 0, currentIndex > 0 {
            dragY = dy
        } else {
            dragY = dy / 3.5   // rubber-band at edges
        }
    }

    private func commitVertical(velocity: CGFloat, height: CGFloat) {
        guard !isBrowsing else { return }
        let past  = abs(dragY) > height * 0.3
        let flick = abs(velocity) > 600

        if dragY < 0, (past || flick), currentIndex < store.vibes.count - 1 {
            navigateTo(currentIndex + 1, direction: -height)
        } else if dragY > 0, (past || flick), currentIndex > 0 {
            navigateTo(currentIndex - 1, direction: height)
        } else {
            snapBackVertical()
        }
    }

    private func navigateTo(_ newIndex: Int, direction endY: CGFloat) {
        isBrowsing = true
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            dragY = endY
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            currentIndex = newIndex
            dragY        = 0
            isBrowsing   = false
        }
    }

    private func snapBackVertical() {
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            dragY = 0
        }
    }

    // MARK: - Footer (view mode)

    @ViewBuilder
    private func viewModeFooter(vibe: Vibe, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)

                VStack(alignment: .leading, spacing: 6) {
                    Text(vibe.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)

                    HStack(alignment: .center, spacing: 0) {
                        Text("Vibed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))

                        Text("  ·  ")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.system(size: 12))

                        Text(vibe.createdAt, style: .relative)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 11, weight: .medium))
                            Text("Double tap to interact")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, safeBottom + 16)
            }
        }
    }
}

#Preview {
    ContentView()
}
