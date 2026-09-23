import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warm = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let mutedBlue = Color(red: 0.43, green: 0.62, blue: 0.69)
    static let lightBlue = Color(red: 0.78, green: 0.89, blue: 0.97)
    static let background = Color(red: 0.91, green: 0.97, blue: 0.92)
    static let version = "V0.4.1"
    static let buildDate = "20260909"
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
