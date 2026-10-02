import SwiftUI

struct AddButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpening = false

    let action: () -> Void

    var body: some View {
        Button {
            guard !isOpening else { return }
            isOpening = true
            if reduceMotion {
                action()
                isOpening = false
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    action()
                    isOpening = false
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .sakuraGlassBackground(shape: Circle())
                .clipShape(Circle())
                .shadow(color: Constants.accentPink.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(AddButtonBounceStyle())
        .accessibilityLabel("添加作品")
    }
}

private struct AddButtonBounceStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.1 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.52),
                value: configuration.isPressed
            )
    }
}

#Preview {
    AddButton {}
        .padding()
}
