import SwiftUI
import AppKit

struct ImmersiveViewer: View {
    @EnvironmentObject var m: DemoModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let photo = m.current {
                    Image(nsImage: photo.image)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityLabel(photo.title)
                    VStack(spacing: 0) {
                        header(photo)
                        Spacer()
                        controls.padding(.bottom, 28)
                    }
                    .foregroundStyle(.white)
                    .opacity(m.controlsVisible ? 1 : 0)
                    .allowsHitTesting(m.controlsVisible)
                    .accessibilityHidden(!m.controlsVisible)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: m.controlsVisible)
                }
            }
        }
        .coordinateSpace(name: "immersiveViewer")
        .onPreferenceChange(ViewerControlFramesKey.self) { frames in
            (NSApp.delegate as? DemoDelegate)?.viewerControlFrames = frames
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .onDisappear {
            m.viewerControlsHovered = false
            (NSApp.delegate as? DemoDelegate)?.viewerControlFrames = [:]
        }
    }

    private func header(_ photo: SamplePhoto) -> some View {
        HStack(spacing: 14) {
            Button { m.viewing = false } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(QuietToolbarStyle())
            .help("退出全屏 · Esc").accessibilityLabel("退出全屏")
            VStack(alignment: .leading, spacing: 5) {
                Text(photo.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text("\(photo.filename)  ·  \(Int(photo.image.size.width)) × \(Int(photo.image.size.height))  ·  JPEG")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 20)
            Text("\((m.visible.firstIndex { $0.id == m.selection } ?? 0) + 1) / \(m.visible.count)")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.72))
                .accessibilityLabel("第 \((m.visible.firstIndex { $0.id == m.selection } ?? 0) + 1) 张，共 \(m.visible.count) 张")
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.78), .clear], startPoint: .top, endPoint: .bottom))
        .contentShape(Rectangle())
        .background(controlFrame("header"))
        .onHover(perform: holdControls)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            navigationButton("chevron.left", title: "上一张", offset: -1, disabled: m.visible.first?.id == m.selection)
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18).accessibilityHidden(true)
            RatingControl()
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18).accessibilityHidden(true)
            navigationButton("chevron.right", title: "下一张", offset: 1, disabled: m.visible.last?.id == m.selection)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .background(controlFrame("dock"))
        .onHover(perform: holdControls)
    }

    private func navigationButton(_ symbol: String, title: String, offset: Int, disabled: Bool) -> some View {
        Button { m.step(offset) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 30)
        }
        .buttonStyle(QuietToolbarStyle())
        .disabled(disabled)
        .accessibilityLabel(title).help(title + (offset < 0 ? " · ←" : " · →"))
    }

    private func controlFrame(_ name: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ViewerControlFramesKey.self,
                                   value: [name: geometry.frame(in: .named("immersiveViewer"))])
        }
        .allowsHitTesting(false)
    }

    private func holdControls(_ hovering: Bool) {
        // Native coordinates are authoritative; nested SwiftUI tracking areas can
        // otherwise deliver a late exit after the pointer entered another control.
        (NSApp.delegate as? DemoDelegate)?.revealControls()
    }
}

private struct ViewerControlFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}
