// Vibed/ContentView.swift

import SwiftUI

// MARK: - GestureAxis

private enum GestureAxis { case horizontal, vertical }

// MARK: - ContentView

struct ContentView: View {

    // ── Store ──────────────────────────────────────────────────────────────────

    @StateObject private var store = VibeStore()

    // ── Vertical feed state ───────────────────────────────────────────────────

    @State private var currentIndex    = 0
    @State private var displayIndex    = 0
    @State private var targetIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isTransitioning = false

    // ── Horizontal nav state ──────────────────────────────────────────────────
    // horizontalOffset == 0       → feed visible
    // horizontalOffset == -width  → account panel visible (left swipe)

    @State private var horizontalOffset: CGFloat = 0

    // ── Unified gesture state ─────────────────────────────────────────────────

    @State private var gestureAxis: GestureAxis? = nil
    @State private var panBaseH: CGFloat = 0

    // ── Overlay state ──────────────────────────────────────────────────────────

    @State private var overlayVisible = true
    @State private var overlayHideTask: Task<Void, Never>?

    // ── "Vibed." toast ────────────────────────────────────────────────────────

    @State private var showVibedToast = false
    @State private var toastTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // ── Account panel (left) ───────────────────────────────────
                AccountView()
                    .environmentObject(store)
                    .offset(x: horizontalOffset + geo.size.width)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                if gestureAxis == nil {
                                    panBaseH = horizontalOffset
                                }
                                handleDrag(
                                    CGPoint(x: value.translation.width,
                                            y: value.translation.height),
                                    size: geo.size
                                )
                            }
                            .onEnded { value in
                                handleDragEnd(
                                    CGPoint(x: value.velocity.width,
                                            y: value.velocity.height),
                                    size: geo.size
                                )
                            }
                    )

                // ── Feed panel ─────────────────────────────────────────────
                ZStack {
                    vibeStack(size: geo.size)

                    feedOverlay(safeBottom: geo.safeAreaInsets.bottom)
                        .opacity(overlayVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: overlayVisible)
                        .allowsHitTesting(false)
                }
                .offset(x: horizontalOffset)

                // ── "Vibed." toast ─────────────────────────────────────────
                if showVibedToast {
                    Text("Vibed.")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(.black.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                scheduleOverlayHide()
            }
            .onChange(of: store.vibes.count) { oldCount, newCount in
                let newIndex = newCount - 1
                currentIndex   = newIndex
                displayIndex   = newIndex
                targetIndex    = nil
                dragOffset     = 0
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
                    horizontalOffset = 0
                }
                presentToast()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Vibe stack

    @ViewBuilder
    private func vibeStack(size: CGSize) -> some View {
        if let ti = targetIndex {
            let sign: CGFloat = ti > currentIndex ? 1 : -1
            VibeRenderer(vibe: store.vibes[ti])
                .ignoresSafeArea()
                .offset(y: sign * size.height + dragOffset)
        }

        VibeRenderer(
            vibe: store.vibes[currentIndex],
            onDragBegan: {
                panBaseH    = horizontalOffset
                gestureAxis = nil
            },
            onDragChanged: { pt in handleDrag(pt, size: size) },
            onDragEnded:   { pt in handleDragEnd(pt, size: size) }
        )
        .ignoresSafeArea()
        .offset(y: dragOffset)
    }

    // MARK: - Unified gesture handler

    private func handleDrag(_ pt: CGPoint, size: CGSize) {
        guard !isTransitioning else { return }

        if gestureAxis == nil {
            let ax = abs(pt.x), ay = abs(pt.y)
            guard ax > 20 || ay > 20 else { return }
            gestureAxis = ax > ay * 1.5 ? .horizontal : .vertical
        }

        switch gestureAxis! {
        case .horizontal:
            handleHorizontalDrag(dx: pt.x, width: size.width)
        case .vertical:
            showOverlay()
            handleVerticalDrag(dy: pt.y, height: size.height)
        }
    }

    private func handleDragEnd(_ pt: CGPoint, size: CGSize) {
        defer { gestureAxis = nil }
        guard !isTransitioning else { return }

        switch gestureAxis {
        case .horizontal: commitHorizontal(velocity: pt.x, width: size.width)
        case .vertical:   commitVertical(velocity: pt.y, height: size.height)
        case nil:         snapBackVertical()
        }
    }

    // MARK: Horizontal (feed ↔ account)

    private func handleHorizontalDrag(dx: CGFloat, width: CGFloat) {
        if panBaseH < 0 {
            // In account: rightward closes, leftward rubber-bands
            let target = panBaseH + dx
            horizontalOffset = max(-width, min(0, target))
        } else {
            // In feed: only leftward drag opens account
            horizontalOffset = max(-width, min(0, dx))
        }
    }

    private func commitHorizontal(velocity: CGFloat, width: CGFloat) {
        let moved     = abs(horizontalOffset - panBaseH)
        let threshold = width * 0.3
        let fast      = abs(velocity) > 600

        let snapTarget: CGFloat
        if panBaseH < 0 {
            let close = (moved > threshold || fast) && velocity > 0
            snapTarget = close ? 0 : -width
        } else {
            if (fast && velocity < 0) || horizontalOffset < -threshold {
                snapTarget = -width
            } else {
                snapTarget = 0
            }
        }

        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            horizontalOffset = snapTarget
        }
    }

    // MARK: Vertical (feed navigation)

    private func handleVerticalDrag(dy: CGFloat, height: CGFloat) {
        if dy < 0, currentIndex < store.vibes.count - 1 {
            targetIndex = currentIndex + 1
            dragOffset  = dy
        } else if dy > 0, currentIndex > 0 {
            targetIndex = currentIndex - 1
            dragOffset  = dy
        } else {
            targetIndex = nil
            dragOffset  = dy / 3.5
        }
    }

    private func commitVertical(velocity: CGFloat, height: CGFloat) {
        let pastThreshold = abs(dragOffset) > height * 0.3
        let fastFlick     = abs(velocity)   > 600

        let goNext = (pastThreshold || fastFlick) && dragOffset < 0 && currentIndex < store.vibes.count - 1
        let goPrev = (pastThreshold || fastFlick) && dragOffset > 0 && currentIndex > 0

        if      goNext { commitVerticalTransition(to: currentIndex + 1, height: height) }
        else if goPrev { commitVerticalTransition(to: currentIndex - 1, height: height) }
        else           { snapBackVertical() }
    }

    private func commitVerticalTransition(to newIndex: Int, height: CGFloat) {
        isTransitioning = true
        displayIndex    = newIndex

        let endOffset: CGFloat = newIndex > currentIndex ? -height : height
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            dragOffset = endOffset
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            currentIndex    = newIndex
            targetIndex     = nil
            dragOffset      = 0
            isTransitioning = false
        }

        scheduleOverlayHide()
    }

    private func snapBackVertical() {
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            dragOffset = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            targetIndex = nil
        }
    }

    // MARK: - Overlay visibility

    private func showOverlay() {
        overlayHideTask?.cancel()
        overlayVisible = true
        scheduleOverlayHide()
    }

    private func scheduleOverlayHide() {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            overlayVisible = false
        }
    }

    // MARK: - Toast

    private func presentToast() {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showVibedToast = true
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.4)) {
                showVibedToast = false
            }
        }
    }

    // MARK: - Feed overlay UI

    @ViewBuilder
    private func feedOverlay(safeBottom: CGFloat) -> some View {
        let vibe = store.vibes[displayIndex]

        VStack(spacing: 0) {
            Spacer()

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vibe.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                        if !vibe.description.isEmpty {
                            Text(vibe.description)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                        }
                    }

                    Spacer()

                    // Position dots
                    HStack(spacing: 5) {
                        ForEach(store.vibes.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == displayIndex
                                      ? Color.white
                                      : Color.white.opacity(0.38))
                                .frame(width: i == displayIndex ? 20 : 6, height: 6)
                                .animation(
                                    .spring(response: 0.28, dampingFraction: 0.72),
                                    value: displayIndex
                                )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, safeBottom + 14)
            }
        }
    }
}

#Preview {
    ContentView()
}
