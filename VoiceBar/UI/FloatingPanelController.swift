import AppKit
import SwiftUI

final class FloatingPanelController {
    private var panel: NSPanel!
    private var hostingView: NSHostingView<WaveformContentView>!
    private var contentModel = WaveformModel()

    init() {
        setupPanel()
    }

    private func setupPanel() {
        let panelWidth: CGFloat = 240
        let panelHeight: CGFloat = 56
        let bottomPadding: CGFloat = 80

        // macOS screen coords: origin at bottom-left
        // y = bottomPadding places panel at bottom of screen
        let frame = NSRect(
            x: (NSScreen.main?.frame.width ?? 1200) / 2 - panelWidth / 2,
            y: bottomPadding,
            width: panelWidth,
            height: panelHeight
        )

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let contentView = WaveformContentView(model: contentModel)
        hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.masksToBounds = true

        panel.contentView = hostingView
    }

    func show() {
        let screenWidth = NSScreen.main?.frame.width ?? 1200
        let bottomPadding: CGFloat = 80

        panel.setFrameOrigin(NSPoint(x: screenWidth / 2 - 120, y: bottomPadding))
        panel.orderFrontRegardless()

        contentModel.transcriptionText = ""
        contentModel.waveformLevel = 0
        contentModel.isRecording = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1.0
            panel.animator().setFrame(NSRect(x: screenWidth / 2 - 120, y: bottomPadding, width: 240, height: 56), display: true)
        }, completionHandler: nil)
    }

    func hide() {
        contentModel.isRecording = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setContentSize(NSSize(width: 60, height: 56))
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.contentModel.transcriptionText = ""
            self.contentModel.waveformLevel = 0
        })
    }

    func updateTranscription(_ text: String) {
        contentModel.transcriptionText = text

        let textWidth = min(560, max(160, CGFloat(text.count) * 9 + 80))
        let bottomPadding: CGFloat = 80
        let screenWidth = NSScreen.main?.frame.width ?? 1200

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            let newFrame = NSRect(
                x: screenWidth / 2 - textWidth / 2,
                y: bottomPadding,
                width: textWidth,
                height: 56
            )
            panel.animator().setFrame(newFrame, display: true)
        }, completionHandler: nil)
    }

    func setWaveformLevel(_ level: Float) {
        contentModel.waveformLevel = level
    }
}

// MARK: - Shared Model

final class WaveformModel: ObservableObject {
    @Published var transcriptionText: String = ""
    @Published var waveformLevel: Float = 0
    @Published var isRecording: Bool = false
}

// MARK: - Waveform View

struct WaveformContentView: View {
    @ObservedObject var model: WaveformModel

    @State private var bar1: CGFloat = 3
    @State private var bar2: CGFloat = 3
    @State private var bar3: CGFloat = 3
    @State private var bar4: CGFloat = 3
    @State private var bar5: CGFloat = 3

    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barWidth: CGFloat = 3
    private let waveformHeight: CGFloat = 32

    var body: some View {
        // Waveform always anchored to LEFT, text expands rightward
        HStack(spacing: 12) {
            // Waveform bars - fixed at left edge
            HStack(spacing: 3) {
                WaveformBar(height: bar1, width: barWidth)
                WaveformBar(height: bar2, width: barWidth)
                WaveformBar(height: bar3, width: barWidth)
                WaveformBar(height: bar4, width: barWidth)
                WaveformBar(height: bar5, width: barWidth)
            }
            .frame(width: 44, height: waveformHeight)

            // Transcription text - grows from waveform right edge
            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: 480, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 56)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black.opacity(0.25))
            }
            .cornerRadius(28)
        )
        .onChange(of: model.waveformLevel) { _, newLevel in
            animateBars(to: CGFloat(newLevel))
        }
    }

    private var displayText: String {
        if !model.transcriptionText.isEmpty {
            return model.transcriptionText
        }
        return model.isRecording ? "..." : ""
    }

    private func animateBars(to level: CGFloat) {
        let targets = barWeights.map { weight -> CGFloat in
            let h = level * waveformHeight * weight
            return min(waveformHeight * weight, max(3, h))
        }

        withAnimation(.easeOut(duration: 0.12)) { bar1 = targets[0] }
        withAnimation(.easeOut(duration: 0.14)) { bar2 = targets[1] }
        withAnimation(.easeOut(duration: 0.10)) { bar3 = targets[2] }
        withAnimation(.easeOut(duration: 0.13)) { bar4 = targets[3] }
        withAnimation(.easeOut(duration: 0.15)) { bar5 = targets[4] }
    }
}

struct WaveformBar: View {
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: max(3, height))
    }
}
