// Vibed/ContentView.swift

import SwiftUI

struct ContentView: View {

    // ── Feed state ─────────────────────────────────────────────────────────────

    /// Which VibeRenderer is "current" for offset / layout math.
    @State private var currentIndex = 0

    /// Updated immediately when the user commits to a navigation; drives the
    /// overlay text so the title switches as the animation begins, not after.
    @State private var displayIndex = 0

    /// Non-nil only while a drag or spring animation is in flight; holds the
    /// index of the Vibe sliding in behind the current one.
    @State private var targetIndex: Int? = nil

    /// Cumulative Y translation of the active drag or spring animation.
    @State private var dragOffset: CGFloat = 0

    /// Prevents new gestures from interrupting a running commit animation.
    @State private var isTransitioning = false

    // ── Overlay state ──────────────────────────────────────────────────────────

    @State private var overlayVisible = true
    @State private var overlayHideTask: Task<Void, Never>?

    // ── First-launch hint state ────────────────────────────────────────────────

    @State private var showSwipeHint = true
    @State private var hintDotPhase  = false   // drives the animated dots

    // ── Data ───────────────────────────────────────────────────────────────────

    private let vibes = Vibe.samples

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                vibeStack(height: geo.size.height)

                feedOverlay(safeBottom: geo.safeAreaInsets.bottom)
                    .opacity(overlayVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: overlayVisible)
                    .allowsHitTesting(false)

                swipeHint
                    .allowsHitTesting(false)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            scheduleOverlayHide()
            scheduleHintDismiss()
        }
    }

    // MARK: - Vibe stack

    @ViewBuilder
    private func vibeStack(height: CGFloat) -> some View {
        // Adjacent Vibe — rendered first, sits BEHIND the current one.
        if let ti = targetIndex {
            let sign: CGFloat = ti > currentIndex ? 1 : -1
            VibeRenderer(vibe: vibes[ti])
                .ignoresSafeArea()
                .offset(y: sign * height + dragOffset)
        }

        // Current Vibe — always on top; slides away on commit.
        VibeRenderer(
            vibe: vibes[currentIndex],
            onDragChanged: handleDrag,
            onDragEnded: { v in handleDragEnd(velocity: v, height: height) }
        )
        .ignoresSafeArea()
        .offset(y: dragOffset)
    }

    // MARK: - Gesture callbacks (fired by VibeRenderer's two-finger pan)

    private func handleDrag(_ dy: CGFloat) {
        guard !isTransitioning else { return }
        showOverlay()
        dismissHint()

        if dy < 0, currentIndex < vibes.count - 1 {
            targetIndex = currentIndex + 1
            dragOffset = dy
        } else if dy > 0, currentIndex > 0 {
            targetIndex = currentIndex - 1
            dragOffset = dy
        } else {
            // Rubber-band resistance past the feed edges
            targetIndex = nil
            dragOffset = dy / 3.5
        }
    }

    private func handleDragEnd(velocity: CGFloat, height: CGFloat) {
        guard !isTransitioning else { return }

        let pastThreshold = abs(dragOffset) > height * 0.3
        let fastFlick     = abs(velocity)   > 600

        let goNext = (pastThreshold || fastFlick) && dragOffset < 0 && currentIndex < vibes.count - 1
        let goPrev = (pastThreshold || fastFlick) && dragOffset > 0 && currentIndex > 0

        if      goNext { commit(to: currentIndex + 1, height: height) }
        else if goPrev { commit(to: currentIndex - 1, height: height) }
        else           { snapBack() }
    }

    // MARK: - Transition logic

    private func commit(to newIndex: Int, height: CGFloat) {
        isTransitioning = true
        displayIndex = newIndex                                 // overlay switches immediately
        dismissHint()

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

    private func snapBack() {
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

    // MARK: - Swipe hint

    private func dismissHint() {
        guard showSwipeHint else { return }
        withAnimation(.easeOut(duration: 0.35)) { showSwipeHint = false }
    }

    private func scheduleHintDismiss() {
        // Animate the pulsing dots
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            hintDotPhase = true
        }
        // Auto-dismiss after 5 seconds if user hasn't swiped
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut(duration: 0.5)) { showSwipeHint = false }
        }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if showSwipeHint {
            VStack(spacing: 14) {
                // Two animated upward-pointing arrows
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(y: hintDotPhase ? -4 : 4)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                                value: hintDotPhase
                            )
                    }
                }

                Text("Two-finger swipe to explore")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(0.2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.88)))
        }
    }

    // MARK: - Overlay UI

    @ViewBuilder
    private func feedOverlay(safeBottom: CGFloat) -> some View {
        let vibe = vibes[displayIndex]

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
                        Text(vibe.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                    }

                    Spacer()

                    // Position dots — active dot expands to a capsule
                    HStack(spacing: 5) {
                        ForEach(vibes.indices, id: \.self) { i in
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
