import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warm = Color(red: 0.96, green: 0.73, blue: 0.30)
    static let mutedBlue = Color(red: 0.43, green: 0.62, blue: 0.69)
    static let lightBlue = Color(red: 0.78, green: 0.89, blue: 0.97)
    static let background = Color(red: 0.91, green: 0.97, blue: 0.92)
    static let version = "V0.1.3"
    static let buildDate = "20260907"
}

struct AppFooter: View {
    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 32, height: 32)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text("\(AppTheme.version) (\(AppTheme.buildDate))")
                Text("By Atex Lin")
            }
            Spacer(minLength: 0)
            NavigationLink {
                ErrorLogView()
            } label: {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("程式錯誤紀錄")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 1)
    }
}
