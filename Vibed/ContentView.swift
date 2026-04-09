// Vibed/ContentView.swift

import SwiftUI

// MARK: - ContentView

struct ContentView: View {

    @StateObject private var store = VibeStore()
    @StateObject private var pool  = VibePreloadPool()
    @EnvironmentObject private var auth: AuthManager

    // ── Feed state ─────────────────────────────────────────────────────────────
    @State private var currentIndex  = 0
    @State private var isInteractive = false

    // ── Carousel drag ──────────────────────────────────────────────────────────
    // dragY offsets ALL cards simultaneously — no webview swapping needed.
    // When navigate fires: currentIndex += 1, dragY = 0 are set atomically.
    // Because card position = (i - currentIndex)*height + dragY, both values
    // cancel out and visible cards don't jump.
    @State private var dragY:     CGFloat = 0
    @State private var isBrowsing         = false

    // ── Horizontal nav (feed ↔ account) ───────────────────────────────────────
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
                    .environmentObject(auth)
                    .offset(x: horizontalOffset + geo.size.width)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { v in
                                if v.translation.width > 0 {
                                    horizontalOffset = max(-geo.size.width,
                                                          min(0, -geo.size.width + v.translation.width))
                                }
                            }
                            .onEnded { v in
                                let close = v.translation.width > geo.size.width * 0.3
                                           || v.velocity.width > 500
                                withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
                                    horizontalOffset = close ? 0 : -geo.size.width
                                }
                            }
                    )

                // ── Feed panel ─────────────────────────────────────────────────
                ZStack {
                    carousel(size: geo.size)

                    if !isInteractive {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(feedGesture(geo: geo))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isInteractive = true
                                }
                            }

                        if !store.vibes.isEmpty && currentIndex < store.vibes.count {
                            viewModeFooter(
                                vibe: store.vibes[currentIndex],
                                safeBottom: geo.safeAreaInsets.bottom
                            )
                            .allowsHitTesting(false)
                        }

                        // Spinner while the current vibe's ZIP is downloading
                        let currentVibeID = store.vibes.indices.contains(currentIndex)
                            ? store.vibes[currentIndex].id : nil
                        if let id = currentVibeID, pool.downloadingIDs.contains(id) {
                            ZStack {
                                Color.black.opacity(0.6)
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.4)
                            }
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .allowsHitTesting(false)
                        }
                    }

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
            .onAppear {
                pool.prime(around: currentIndex, vibes: store.vibes)
            }
            .onChange(of: currentIndex) { oldIndex, newIndex in
                // Reload old slot off-screen so it restarts fresh on next visit
                if oldIndex < store.vibes.count {
                    pool.resetSlot(index: oldIndex, vibe: store.vibes[oldIndex])
                }
                pool.prime(around: newIndex, vibes: store.vibes)
            }
            .onChange(of: store.vibes.count) { _, _ in
                pool.prime(around: currentIndex, vibes: store.vibes)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: isInteractive)
        .animation(.easeInOut(duration: 0.2), value: pool.downloadingIDs.isEmpty)
    }

    // MARK: - Carousel

    // All cards are positioned by formula: y = (i - currentIndex) * height + dragY
    // This means every card moves together. Changing currentIndex+dragY atomically
    // produces zero visual discontinuity — no webview needs to change containers.
    @ViewBuilder
    private func carousel(size: CGSize) -> some View {
        if !store.vibes.isEmpty {
            let lo = max(0, currentIndex - 2)
            let hi = min(store.vibes.count - 1, currentIndex + 2)

            ForEach(lo...hi, id: \.self) { i in
                VibeCardView(
                    webView: pool.webView(at: i),
                    isInteractive: isInteractive && i == currentIndex
                )
                .ignoresSafeArea()
                .offset(y: CGFloat(i - currentIndex) * size.height + dragY)
            }
        }
    }

    // MARK: - Gestures

    private func feedGesture(geo: GeometryProxy) -> some Gesture {
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
                    if v.translation.width < 0 {
                        horizontalOffset = max(-geo.size.width, v.translation.width)
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
                case .horizontal: commitHorizontal(velocity: v.velocity.width, width: geo.size.width)
                case .vertical:   commitVertical(velocity: v.velocity.height, height: geo.size.height)
                case nil:         snapBack()
                }
            }
    }

    // MARK: Horizontal

    private func commitHorizontal(velocity: CGFloat, width: CGFloat) {
        let open = abs(horizontalOffset) > width * 0.3 || velocity < -500
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            horizontalOffset = open ? -width : 0
        }
    }

    // MARK: Vertical

    private func handleVerticalDrag(dy: CGFloat, height: CGFloat) {
        guard !isBrowsing else { return }
        let canGoNext = currentIndex < store.vibes.count - 1
        let canGoPrev = currentIndex > 0
        if dy < 0 && canGoNext {
            dragY = dy
        } else if dy > 0 && canGoPrev {
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
            navigate(to: currentIndex + 1, endY: -height)
        } else if dragY > 0, (past || flick), currentIndex > 0 {
            navigate(to: currentIndex - 1, endY: height)
        } else {
            snapBack()
        }
    }

    private func navigate(to newIndex: Int, endY: CGFloat) {
        isBrowsing = true
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            dragY = endY
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            // Atomic: card positions don't change because
            // (i - newIndex)*height + 0  ==  (i - oldIndex)*height + endY  for i == newIndex
            currentIndex = newIndex
            dragY        = 0
            isBrowsing   = false
        }
    }

    private func snapBack() {
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
