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
    // horizontalOffset == 0        → feed visible
    // horizontalOffset == width    → editor visible

    @State private var horizontalOffset: CGFloat = 0

    // ── Unified gesture state ─────────────────────────────────────────────────

    @State private var gestureAxis: GestureAxis? = nil
    @State private var panBaseH: CGFloat = 0    // horizontalOffset at gesture start

    // ── Overlay state ──────────────────────────────────────────────────────────

    @State private var overlayVisible = true
    @State private var overlayHideTask: Task<Void, Never>?

    // ── Swipe hint ─────────────────────────────────────────────────────────────

    @State private var showSwipeHint = true
    @State private var hintDotPhase  = false

    // ── "Vibed." toast ────────────────────────────────────────────────────────

    @State private var showVibedToast = false
    @State private var toastTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // ── Feed panel ─────────────────────────────────────────────
                ZStack {
                    vibeStack(size: geo.size)

                    feedOverlay(safeBottom: geo.safeAreaInsets.bottom)
                        .opacity(overlayVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4), value: overlayVisible)
                        .allowsHitTesting(false)

                    swipeHint
                        .allowsHitTesting(false)
                }
                .offset(x: horizontalOffset)

                // ── Editor panel ───────────────────────────────────────────
                EditorGestureContainer(
                    onDragBegan: {
                        panBaseH   = horizontalOffset
                        gestureAxis = nil
                    },
                    onDragChanged: { pt in handleDrag(pt, size: geo.size) },
                    onDragEnded:   { pt in handleDragEnd(pt, size: geo.size) }
                )
                .environmentObject(store)
                .offset(x: horizontalOffset - geo.size.width)

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
                scheduleHintDismiss()
            }
            .onChange(of: store.vibes.count) { newCount in
                // A new vibe was published — jump to it and close editor
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

        // Wait for at least 20 pts of movement in any direction, then commit to
        // whichever axis dominates. The prior guard-on-both-axes approach could
        // deadlock (neither condition passing) and let vertical lock too eagerly
        // during an intentional horizontal swipe.
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
            dismissHint()
            handleVerticalDrag(dy: pt.y, height: size.height)
        }
    }

    private func handleDragEnd(_ pt: CGPoint, size: CGSize) {
        defer { gestureAxis = nil }
        guard !isTransitioning else { return }

        switch gestureAxis {
        case .horizontal:
            commitHorizontal(velocity: pt.x, width: size.width)
        case .vertical:
            commitVertical(velocity: pt.y, height: size.height)
        case nil:
            // No axis locked — snap everything back
            snapBackVertical()
        }
    }

    // MARK: Horizontal (feed ↔ editor)

    private func handleHorizontalDrag(dx: CGFloat, width: CGFloat) {
        if panBaseH < 1 {
            // In feed: rightward drag opens editor; leftward rubber-bands
            horizontalOffset = dx > 0 ? min(dx, width) : dx / 3.5
        } else {
            // In editor: leftward drag closes; rightward rubber-bands
            let target = width + dx
            horizontalOffset = dx < 0 ? max(target, 0) : width + dx / 3.5
        }
    }

    private func commitHorizontal(velocity: CGFloat, width: CGFloat) {
        let moved     = abs(horizontalOffset - panBaseH)
        let threshold = width * 0.3
        let fast      = abs(velocity) > 600

        let snapTarget: CGFloat
        if panBaseH < 1 {
            // Starting from feed — commit to editor if dragged/flicked right
            let open = (moved > threshold || fast) && velocity > -200
            snapTarget = open ? width : 0
        } else {
            // Starting from editor — commit to feed if dragged/flicked left
            let close = (moved > threshold || fast) && velocity < 200
            snapTarget = close ? 0 : width
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

    // MARK: - Swipe hint

    private func dismissHint() {
        guard showSwipeHint else { return }
        withAnimation(.easeOut(duration: 0.35)) { showSwipeHint = false }
    }

    private func scheduleHintDismiss() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            hintDotPhase = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut(duration: 0.5)) { showSwipeHint = false }
        }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if showSwipeHint {
            VStack(spacing: 16) {
                // ── Vertical hint ──────────────────────────────────────────
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { i in
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(y: hintDotPhase ? -3 : 3)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.15),
                                    value: hintDotPhase
                                )
                        }
                    }
                    Text("Explore vibes")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                // ── Horizontal hint ────────────────────────────────────────
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: hintDotPhase ? 3 : -3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true),
                            value: hintDotPhase
                        )
                    Text("Create a vibe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.15), lineWidth: 1))
            .transition(.opacity.combined(with: .scale(scale: 0.88)))
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
