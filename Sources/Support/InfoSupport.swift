import SwiftUI

struct InfoTipButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("說明：\(title)")
        .alert(title, isPresented: $isPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct InfoSectionHeader: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            InfoTipButton(title: title, message: message)
                .textCase(nil)
        }
    }
}
