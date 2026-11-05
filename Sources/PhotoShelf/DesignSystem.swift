import SwiftUI
import AppKit

/// Small-size version of the app icon's stacked sunset photographs.
struct PhotoShelfMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.53, green: 0.67, blue: 0.89))
                .frame(width: 17, height: 17)
                .rotationEffect(.degrees(-9)).offset(x: -2, y: -2)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(red: 0.34, green: 0.36, blue: 0.75), Color(red: 0.75, green: 0.52, blue: 0.76)], startPoint: .top, endPoint: .bottom))
                Circle().fill(Color(red: 1, green: 0.73, blue: 0.40))
                    .frame(width: 5, height: 5).offset(x: 3.5, y: -2.5)
                Canvas { context, size in
                    var hill = Path()
                    hill.move(to: CGPoint(x: 0, y: size.height * 0.66))
                    hill.addCurve(to: CGPoint(x: size.width, y: size.height * 0.76), control1: CGPoint(x: size.width * 0.36, y: size.height * 0.34), control2: CGPoint(x: size.width * 0.62, y: size.height * 0.94))
                    hill.addLine(to: CGPoint(x: size.width, y: size.height))
                    hill.addLine(to: CGPoint(x: 0, y: size.height))
                    hill.closeSubpath()
                    context.fill(hill, with: .color(Color(red: 0.16, green: 0.20, blue: 0.43)))
                }.clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(width: 15, height: 15).padding(2)
            .background(Color(red: 0.98, green: 0.95, blue: 0.88), in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(colorScheme == .dark ? 0 : 0.09), lineWidth: 0.5) }
            .offset(x: 1.5, y: 1.5)
        }
        .accessibilityHidden(true)
    }
}

struct DesignPalette {
    let dark: Bool
    var canvas: Color { Color(white: dark ? 0.105 : 0.985) }
    var panel: Color { Color(white: dark ? 0.135 : 0.955) }
    var inspector: Color { Color(white: dark ? 0.12 : 0.975) }
    var raised: Color { Color(white: dark ? 0.19 : 0.91) }
    var line: Color { Color.primary.opacity(dark ? 0.085 : 0.08) }
    var muted: Color { Color(white: dark ? 0.60 : 0.43) }
    var accent: Color { dark ? Color(red: 0.43, green: 0.62, blue: 0.94) : Color(red: 0.18, green: 0.39, blue: 0.73) }
}

struct QuietToolbarStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FeedbackBody(label:configuration.label,pressed:configuration.isPressed,padding:3) }
}
struct RowFeedbackStyle: ButtonStyle {
    func makeBody(configuration:Configuration)->some View { FeedbackBody(label:configuration.label,pressed:configuration.isPressed,padding:0) }
}
private struct FeedbackBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let padding: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    var body: some View {
        label.padding(padding).contentShape(RoundedRectangle(cornerRadius:5))
            .background(Color.primary.opacity(enabled ? (pressed ? 0.10 : hover ? 0.055 : 0) : 0),in:RoundedRectangle(cornerRadius:5))
            .opacity(enabled ? 1 : 0.3).onHover { hover = $0 && enabled }
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:hover)
    }
}

struct FavoriteButton: View {
    let selected: Bool
    var unselectedColor: Color = .secondary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: selected ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
                .foregroundStyle(selected ? Color.pink : unselectedColor)
        }.buttonStyle(RowFeedbackStyle())
            .help(selected ? "取消收藏（F）" : "添加收藏（F）")
            .accessibilityLabel(selected ? "取消收藏" : "添加收藏")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
