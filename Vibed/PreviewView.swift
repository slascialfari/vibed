// Vibed/PreviewView.swift

import SwiftUI

struct PreviewView: View {
    let vibe: Vibe

    /// Local file URL for multi-file GitHub repo vibes.
    /// When set, VibeRenderer loads from disk instead of vibe.htmlContent.
    var fileURL: URL? = nil

    var onBack: () -> Void
    var onPublish: () -> Void

    @State private var logs: [String] = []
    @State private var showDebug = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VibeRenderer(vibe: vibe, fileURL: fileURL, isInteractive: true, onLog: { entry in
                logs.append(entry)
            })
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: back + debug toggle
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    Spacer()
                    Button {
                        showDebug.toggle()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "ladybug")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(showDebug ? .black : .white)
                                .frame(width: 44, height: 44)
                                .background(showDebug ? .white : .black.opacity(0.55), in: Circle())
                            if !logs.isEmpty {
                                Circle()
                                    .fill(logs.contains(where: { $0.hasPrefix("🔴") }) ? Color.red : Color.yellow)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 60)

                Spacer()

                // Publish button — bottom center
                Button(action: onPublish) {
                    Text("Submit for Approval")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .padding(.bottom, 52)
            }

            // Debug panel
            if showDebug {
                DebugPanel(logs: logs) {
                    logs.removeAll()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showDebug)
    }
}

// MARK: - DebugPanel

private struct DebugPanel: View {
    let logs: [String]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Console")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Clear") { onClear() }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(white: 0.12))

                Divider().overlay(Color.white.opacity(0.1))

                // Log entries
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if logs.isEmpty {
                                Text("No logs yet…")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .padding(14)
                            } else {
                                ForEach(Array(logs.enumerated()), id: \.offset) { idx, entry in
                                    Text(entry)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(entry.hasPrefix("🔴") ? Color.red.opacity(0.9)
                                                       : entry.hasPrefix("🟡") ? Color.yellow.opacity(0.9)
                                                       : Color.white.opacity(0.75))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                        .background(idx % 2 == 0 ? Color.clear : Color.white.opacity(0.03))
                                }
                            }
                        }
                    }
                    .onChange(of: logs.count) { _, _ in
                        if let last = logs.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
                .frame(height: 260)
                .background(Color(white: 0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 60)
        }
    }
}
