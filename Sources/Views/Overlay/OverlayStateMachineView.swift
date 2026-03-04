import SwiftUI
import AVKit
import AppKit

// MARK: - Mascot Video View (fixed-size panel, never moves)

/// Just the video player with context menu and tap gesture.
/// Lives in its own NSPanel that never changes size.
struct OverlayStateMachineView: View {
    let stateMachine: OverlayStateMachine
    let onClose: () -> Void
    let onResize: (OverlaySize) -> Void
    let onDragResize: (Int) -> Void
    let onDragResizeEnd: (Int) -> Void
    let onSnooze: (Int) -> Void

    @AppStorage("overlay_size") private var currentSizePixels: Int = OverlaySize.medium.rawValue
    @AppStorage("overlay_resize_mode") private var resizeMode = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            StateMachineVideoPlayer(
                url: stateMachine.currentVideoURL,
                isLoop: stateMachine.isLoopVideo,
                stateMachine: stateMachine
            )
            .onTapGesture {
                stateMachine.handleClick()
            }

            if resizeMode {
                ResizeHandle(
                    currentSize: currentSizePixels,
                    onDrag: onDragResize,
                    onDragEnd: { size in
                        onDragResizeEnd(size)
                        resizeMode = false
                    }
                )
                .frame(width: 32, height: 32)
            }
        }
    }
}

// MARK: - Stats HUD View (fixed panel directly above mascot)

/// Stats pill and debug HUD. Lives in its own panel that never repositions.
struct StatsHUDView: View {
    let stateMachine: OverlayStateMachine

    @AppStorage("overlay_show_debug") private var showDebug = false
    @AppStorage("overlay_show_stats") private var showStats = true

    var body: some View {
        VStack(spacing: 4) {
            if showDebug {
                DebugHUD(stateMachine: stateMachine)
            }

            if showStats {
                StatsOverlayView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

// MARK: - Permission HUD View (adaptive panel, repositions for screen edges)

/// Permission prompts in a speech bubble. Lives in its own panel that adapts position.
@Observable
final class PermissionHUDConfig {
    var tailSide: TailSide = .bottom
    var tailPercent: CGFloat = 0.80
    var onContentSizeChange: ((CGSize) -> Void)?

    var contentSize: CGSize = CGSize(width: 280, height: 200) {
        didSet {
            guard abs(contentSize.width - oldValue.width) > 2
               || abs(contentSize.height - oldValue.height) > 2 else { return }
            onContentSizeChange?(contentSize)
        }
    }
}

struct PermissionHUDView: View {
    let config: PermissionHUDConfig

    var body: some View {
        PermissionStackView()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { config.contentSize = geo.size }
                    .onChange(of: geo.size) { _, newSize in
                        config.contentSize = newSize
                    }
            })
            .environment(\.speechBubbleTailSide, config.tailSide)
            .environment(\.speechBubbleTailPercent, config.tailPercent)
    }
}

// MARK: - Debug HUD

/// Semi-transparent overlay showing state machine status
struct DebugHUD: View {
    let stateMachine: OverlayStateMachine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(stateMachine.currentNodeName) (\(phaseLabel))")
                .fontWeight(.bold)

            if let lastInput = stateMachine.lastInputChange {
                let ago = timeAgo(stateMachine.lastInputTime)
                Text("\(lastInput) \(ago)")
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let result = stateMachine.lastMatchResult {
                Text(result)
                    .foregroundStyle(result.contains("Matched") ? .green : .orange)
            }

            if !stateMachine.availableEdges.isEmpty {
                Divider().background(.white.opacity(0.3))
                ForEach(stateMachine.availableEdges, id: \.self) { edge in
                    Text(edge)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.green)
        .padding(6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .padding(4)
        .allowsHitTesting(false)
    }

    private var phaseLabel: String {
        switch stateMachine.phase {
        case .idle: return "idle"
        case .looping: return "looping"
        case .transitioning: return "transitioning"
        }
    }

    private func timeAgo(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 1 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}

// MARK: - NSViewRepresentable AVPlayer

/// Plays video URLs from the state machine using an A/B double-buffer.
/// Two AVPlayerLayers exist permanently — opacity swap on isReadyForDisplay
/// guarantees frame-perfect transitions with no flicker.
struct StateMachineVideoPlayer: NSViewRepresentable {
    let url: URL?
    let isLoop: Bool
    let stateMachine: OverlayStateMachine

    func makeNSView(context: Context) -> NSView {
        let container = PlayerContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.isOpaque = false

        // Create both layers upfront
        let layerA = AVPlayerLayer()
        layerA.videoGravity = .resizeAspect
        layerA.backgroundColor = .clear
        layerA.isOpaque = false
        layerA.opacity = 1

        let layerB = AVPlayerLayer()
        layerB.videoGravity = .resizeAspect
        layerB.backgroundColor = .clear
        layerB.isOpaque = false
        layerB.opacity = 0

        if let containerLayer = container.layer {
            containerLayer.addSublayer(layerA)
            containerLayer.addSublayer(layerB)
            layerA.frame = containerLayer.bounds
            layerB.frame = containerLayer.bounds
        }

        context.coordinator.container = container
        context.coordinator.stateMachine = stateMachine
        context.coordinator.layerA = layerA
        context.coordinator.layerB = layerB

        // Initial load
        if let url {
            context.coordinator.loadVideo(url: url, loop: isLoop)
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator

        if url != coordinator.currentURL || isLoop != coordinator.currentLoop {
            if let url {
                coordinator.loadVideo(url: url, loop: isLoop)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var container: PlayerContainerView?
        var stateMachine: OverlayStateMachine?

        // A/B double-buffer
        var layerA: AVPlayerLayer?
        var layerB: AVPlayerLayer?
        var playerA: AVPlayer?
        var playerB: AVPlayer?
        private var activeIsA = true

        var currentURL: URL?
        var currentLoop = true
        private var endObserver: NSObjectProtocol?
        private var readyObserver: NSKeyValueObservation?

        private var activePlayer: AVPlayer? { activeIsA ? playerA : playerB }
        private var activeLayer: AVPlayerLayer? { activeIsA ? layerA : layerB }

        func loadVideo(url: URL, loop: Bool) {
            // Clean up pending observers
            if let obs = endObserver {
                NotificationCenter.default.removeObserver(obs)
                endObserver = nil
            }
            readyObserver?.invalidate()
            readyObserver = nil

            currentURL = url
            currentLoop = loop

            let isFirstLoad = playerA == nil && playerB == nil
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = true

            // Load onto the inactive buffer
            let targetLayer: AVPlayerLayer?
            if isFirstLoad {
                // First video — load directly onto A
                playerA = newPlayer
                layerA?.player = newPlayer
                layerA?.opacity = 1
                activeIsA = true
                targetLayer = layerA
            } else if activeIsA {
                playerB = newPlayer
                layerB?.player = newPlayer
                targetLayer = layerB
            } else {
                playerA = newPlayer
                layerA?.player = newPlayer
                targetLayer = layerA
            }

            guard let targetLayer else { return }

            if !isFirstLoad {
                // Wait for the new layer to have a decoded frame, then swap
                let oldPlayer = activePlayer
                let oldLayer = activeLayer
                readyObserver = targetLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                    guard layer.isReadyForDisplay else { return }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        // Instant opacity swap — no implicit animation
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        targetLayer.opacity = 1
                        oldLayer?.opacity = 0
                        CATransaction.commit()
                        oldPlayer?.pause()
                        self.activeIsA.toggle()
                    }
                    self?.readyObserver?.invalidate()
                    self?.readyObserver = nil
                }
            }

            // End-of-video observer
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.currentLoop {
                    self.activePlayer?.seek(to: .zero)
                    self.activePlayer?.play()
                    Task { @MainActor in
                        self.stateMachine?.handleLoopCycleCompleted()
                    }
                } else {
                    Task { @MainActor in
                        self.stateMachine?.handleVideoEnded()
                    }
                }
            }

            newPlayer.play()
        }

        deinit {
            if let obs = endObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            readyObserver?.invalidate()
            playerA?.pause()
            playerB?.pause()
        }
    }
}
