// Vibed/EditorView.swift

import SwiftUI

struct EditorView: View {

    @EnvironmentObject private var store: VibeStore

    @State private var title       = ""
    @State private var code        = ""
    @State private var hasPreviewed = false
    @State private var isPreviewing = false

    private var codeIsEmpty: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled" : t
    }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Title field ────────────────────────────────────────────
                TextField("Name your vibe...", text: $title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 14)

                Divider()
                    .background(Color.white.opacity(0.1))

                // ── Code area ──────────────────────────────────────────────
                TextEditor(text: $code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                Divider()
                    .background(Color.white.opacity(0.1))

                // ── Action buttons ─────────────────────────────────────────
                HStack(spacing: 12) {
                    Button {
                        hasPreviewed = true
                        isPreviewing = true
                    } label: {
                        Text("Preview")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(codeIsEmpty
                                             ? Color.white.opacity(0.3)
                                             : Color.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .background(
                                Color.white.opacity(codeIsEmpty ? 0.04 : 0.1),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(codeIsEmpty ? 0.08 : 0.18),
                                            lineWidth: 1)
                            )
                    }
                    .disabled(codeIsEmpty)

                    Button {
                        store.publish(Vibe(title: resolvedTitle,
                                          description: "",
                                          htmlContent: code))
                    } label: {
                        Text("Publish")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(!hasPreviewed ? Color.black.opacity(0.4) : Color.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .background(
                                Color.white.opacity(!hasPreviewed ? 0.35 : 1),
                                in: Capsule()
                            )
                    }
                    .disabled(!hasPreviewed)
                }
                .padding(20)
            }

            // ── Preview overlay ────────────────────────────────────────────
            if isPreviewing {
                PreviewView(
                    vibe: Vibe(title: resolvedTitle,
                               description: "",
                               htmlContent: code),
                    onBack: {
                        isPreviewing = false
                    },
                    onPublish: {
                        store.publish(Vibe(title: resolvedTitle,
                                          description: "",
                                          htmlContent: code))
                        isPreviewing = false
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPreviewing)
    }
}

// MARK: - EditorGestureContainer
//
// Wraps EditorView in a UIHostingController as a child view controller so we
// can attach a two-finger UIPanGestureRecognizer to the root UIView — the same
// parent-container trick used by VibeRenderer. This lets the two-finger drag
// close the editor while single-finger touches reach the TextEditor unchanged.

struct EditorGestureContainer: UIViewControllerRepresentable {

    var onDragBegan:   () -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded:   (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear

        // Hosting controller carries @EnvironmentObject through SwiftUI's
        // environment, injected by ContentView via .environmentObject(store).
        let host = UIHostingController(rootView: EditorView())
        host.view.backgroundColor = .clear

        vc.addChild(host)
        vc.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: vc.view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
        ])
        host.didMove(toParent: vc)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        vc.view.addGestureRecognizer(pan)

        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update gesture callbacks on every SwiftUI render cycle so closures
        // always reference the latest @State values in ContentView.
        // Do NOT update host.rootView — that would reset EditorView's @State
        // (title, code, etc.) every time ContentView re-renders.
        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDragBegan:   () -> Void        = { }
        var onDragChanged: (CGPoint) -> Void = { _ in }
        var onDragEnded:   (CGPoint) -> Void = { _ in }

        @objc func handlePan(_ r: UIPanGestureRecognizer) {
            switch r.state {
            case .began:
                onDragBegan()
                let t = r.translation(in: r.view)
                onDragChanged(CGPoint(x: t.x, y: t.y))
            case .changed:
                let t = r.translation(in: r.view)
                onDragChanged(CGPoint(x: t.x, y: t.y))
            case .ended, .cancelled, .failed:
                let v = r.velocity(in: r.view)
                onDragEnded(CGPoint(x: v.x, y: v.y))
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gr: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool { false }
    }
}
