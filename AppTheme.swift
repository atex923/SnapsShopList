import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warm = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let mutedBlue = Color(red: 0.43, green: 0.62, blue: 0.69)
    static let lightBlue = Color(red: 0.78, green: 0.89, blue: 0.97)
    static let background = Color(red: 0.91, green: 0.97, blue: 0.92)
    static let overseasBackground = Color(red: 0.89, green: 0.95, blue: 0.99)
    static let overseasCamera = Color(red: 0.72, green: 0.34, blue: 0.40)
    static let version = "V0.11.2"
    static let buildDate = "20260923"
}

enum AppLimits {
    static let maximumPhotos = 5
    static let maximumQuickDraftPhotos = 10
}

enum QuickModeSettings {
    static let showToggleKey = "SnapsShopList.showQuickModeToggle"
}

private struct AppModeBackgroundModifier: ViewModifier {
    @AppStorage(OverseasModeSettings.enabledKey) private var overseasModeEnabled = false

    func body(content: Content) -> some View {
        content.background(overseasModeEnabled ? AppTheme.overseasBackground : AppTheme.background)
    }
}

extension View {
    func appModeBackground() -> some View {
        modifier(AppModeBackgroundModifier())
    }
}

struct RaisedGlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .background(.ultraThinMaterial, in: Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                Circle().stroke(.white.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.10 : 0.20),
                radius: configuration.isPressed ? 2 : 6,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct AppFooter: View {
    var body: some View {
        Text("\(AppTheme.version) (\(AppTheme.buildDate))")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }
}

struct LeadingInfoRow: View {
    let title: String
    let value: String
    var titleWidth: CGFloat = 72
    var valueFont: Font? = nil

    init(_ title: String, _ value: String, titleWidth: CGFloat = 72, valueFont: Font? = nil) {
        self.title = title
        self.value = value
        self.titleWidth = titleWidth
        self.valueFont = valueFont
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: titleWidth, alignment: .leading)
            Text(value)
                .font(valueFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}
