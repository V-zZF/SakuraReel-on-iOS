import SwiftUI

struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .sakuraGlassBackground(shape: Circle())
                .clipShape(Circle())
                .shadow(color: Constants.accentPink.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("添加作品")
    }
}

#Preview {
    AddButton {}
        .padding()
}
