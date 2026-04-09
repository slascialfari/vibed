// Vibed/EditorView.swift

import SwiftUI

struct EditorView: View {

    @EnvironmentObject private var store: VibeStore

    @State private var title        = ""
    @State private var code         = ""
    @State private var hasPreviewed = false
    @State private var previewVibe: Vibe?

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
                TextField("Name your vibe...", text: $title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 64)
                    .padding(.bottom, 14)

                Divider()
                    .background(Color.white.opacity(0.1))

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

                HStack(spacing: 12) {
                    Button {
                        previewVibe = Vibe(title: resolvedTitle,
                                          description: "",
                                          htmlContent: code)
                        hasPreviewed = true
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

            if let vibe = previewVibe {
                PreviewView(
                    vibe: vibe,
                    onBack: { previewVibe = nil },
                    onPublish: {
                        store.publish(vibe)
                        previewVibe = nil
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewVibe)
    }
}

// MARK: - EditorGestureContainer

struct EditorGestureContainer: UIViewControllerRepresentable {

    @EnvironmentObject private var store: VibeStore

    var onDragBegan:   () -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded:   (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear

        let host = UIHostingController(rootView: EditorView().environmentObject(store))
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
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        vc.view.addGestureRecognizer(pan)

        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onDragBegan   = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded   = onDragEnded
    }

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
