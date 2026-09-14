import SwiftUI

struct PlayButtonOverlay: View {
    let playURL: String?

    var body: some View {
        Group {
            if let urlString = playURL, URL(string: urlString) != nil {
                Button {
                    openPlayURL()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Constants.accentPink)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(LibraryPressStyle())
                .accessibilityLabel("播放")
            }
        }
    }

    private func openPlayURL() {
        guard let urlString = playURL, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview("有链接") {
    PlayButtonOverlay(playURL: "https://example.com/movie")
        .frame(width: 160, height: 240)
        .background(Color.gray.opacity(0.1))
}

#Preview("无链接") {
    PlayButtonOverlay(playURL: nil)
        .frame(width: 160, height: 240)
        .background(Color.gray.opacity(0.1))
}
