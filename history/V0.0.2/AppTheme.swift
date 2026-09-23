import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.12, green: 0.55, blue: 0.33)
    static let warm = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let version = "V0.0.2"
    static let buildDate = "20260906"
}

struct AppFooter: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("\(AppTheme.version) (\(AppTheme.buildDate))")
            Text("By Atex Lin")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
