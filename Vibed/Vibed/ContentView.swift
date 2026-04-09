// Vibed/ContentView.swift

import SwiftUI

struct ContentView: View {

    @StateObject private var store = VibeStore()

    // ── Horizontal panel navigation (0 = feed, +width = editor) ───────────────
    @State private var horizontalOffset: CGFloat = 0
    @State private var panBaseH:         CGFloat = 0

    // ── Feed horizontal gesture axis detection ─────────────────────────────────
    @State private var feedDragStarted = false
    @State private var feedAxisDecided = false
    @State private var feedIsHoriz     = false

    // ── Full-page mode ─────────────────────────────────────────────────────────
    @State private var isFullPage    = false
    @State private var fullPageIndex = 0

    // ── "Vibed." toast ────────────────────────────────────────────────────────
    @State private var showVibedToast = false
    @State private var toastTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // ── Feed panel ─────────────────────────────────────────────
                feedPanel(geo: geo)
                    .offset(x: horizontalOffset)

                // ── Editor panel (slides in from right) ────────────────────
                EditorGestureContainer(
                    onDragBegan: { panBaseH = horizontalOffset },
                    onDragChanged: { pt in
                        let t = panBaseH + pt.x
                        horizontalOffset = max(0, min(geo.size.width, t))
                    },
                    onDragEnded: { pt in
                        commitHorizontal(velocity: pt.x, width: geo.size.width)
                    }
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

                // ── Full-page overlay ──────────────────────────────────────
                if isFullPage, store.vibes.indices.contains(fullPageIndex) {
                    fullPageView(vibe: store.vibes[fullPageIndex])
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: isFullPage)
            .onChange(of: store.vibes.count) { _, _ in
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
                    horizontalOffset = 0
                }
                presentToast()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Feed panel

    private func feedPanel(geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.vibes.enumerated()), id: \.element.id) { i, vibe in
                        vibeCard(vibe: vibe, index: i, size: geo.size)
                            .id(vibe.id)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .simultaneousGesture(feedHorizGesture(width: geo.size.width))
            .onChange(of: store.vibes.count) { _, newCount in
                guard newCount > 0 else { return }
                let lastID = store.vibes[newCount - 1].id
                withAnimation { proxy.scrollTo(lastID, anchor: .top) }
            }
        }
    }

    private func vibeCard(vibe: Vibe, index: Int, size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            VibeRenderer(vibe: vibe, enableNavigationGesture: false)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .init(x: 0.5, y: 0.45),
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            cardFooter(vibe: vibe)
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    fullPageIndex = index
                    withAnimation(.easeInOut(duration: 0.22)) { isFullPage = true }
                }
        }
        .frame(width: size.width, height: size.height)
    }

    private func cardFooter(vibe: Vibe) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vibe.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !vibe.description.isEmpty {
                    Text(vibe.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Tap to\ninteract")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }

    // MARK: - Full-page view

    @ViewBuilder
    private func fullPageView(vibe: Vibe) -> some View {
        ZStack(alignment: .bottomLeading) {
            VibeRenderer(vibe: vibe, enableNavigationGesture: false)
                .ignoresSafeArea()

            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isFullPage = false }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                    Text("Feed")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.bottom, 48)
            .padding(.leading, 20)
        }
    }

    // MARK: - Gestures

    /// Rightward swipe on the feed opens the editor.
    private func feedHorizGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                if !feedDragStarted {
                    feedDragStarted = true
                    feedAxisDecided = false
                    feedIsHoriz     = false
                    panBaseH        = horizontalOffset
                }
                if !feedAxisDecided {
                    let dx = abs(v.translation.width), dy = abs(v.translation.height)
                    guard dx > 12 || dy > 12 else { return }
                    feedIsHoriz     = dx > dy * 1.3
                    feedAxisDecided = true
                }
                guard feedIsHoriz else { return }
                // Only allow rightward drag (to editor); clamp at [0, width]
                let t = panBaseH + v.translation.width
                horizontalOffset = max(0, min(width, t))
            }
            .onEnded { v in
                if feedIsHoriz {
                    commitHorizontal(velocity: v.velocity.width, width: width)
                }
                feedDragStarted = false
                feedAxisDecided = false
                feedIsHoriz     = false
            }
    }

    private func commitHorizontal(velocity: CGFloat, width: CGFloat) {
        let moved     = abs(horizontalOffset - panBaseH)
        let threshold = width * 0.3
        let fast      = abs(velocity) > 600

        let snap: CGFloat
        if panBaseH > 0 {
            // In editor: leftward drag closes
            snap = ((moved > threshold || fast) && velocity < 0) ? 0 : width
        } else {
            // In feed: rightward drag opens editor
            if (moved > threshold || fast) && velocity > 0 {
                snap = width
            } else {
                snap = 0
            }
        }

        withAnimation(.interpolatingSpring(stiffness: 260, damping: 28)) {
            horizontalOffset = snap
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
            withAnimation(.easeOut(duration: 0.4)) { showVibedToast = false }
        }
    }
}

#Preview {
    ContentView()
}
