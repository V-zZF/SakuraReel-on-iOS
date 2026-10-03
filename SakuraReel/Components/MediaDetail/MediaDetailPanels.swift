// Layout adapted from AniShelf, Copyright 2024 Samuel He (Apache-2.0).
// Modified for SakuraReel on 2026-10-02. See Resources/ThirdPartyNotices.txt.
import SwiftUI

/// Detail-only surfaces, matching AniShelf's popup geometry.
struct MediaDetailPanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.22), lineWidth: 1) }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.6), lineWidth: 1) }
        }
    }
}

struct MediaDetailSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title).font(.title3.bold())
            } icon: {
                Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Constants.brandTitlePink)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .modifier(MediaDetailPanel())
    }
}

struct MediaDetailDisclosure<Content: View>: View {
    let title: String
    let symbol: String
    @State private var expanded = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Constants.brandTitlePink)
                    Text(title).font(.title3.bold())
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(Constants.brandTitlePink)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }.contentShape(Rectangle())
            }
            .buttonStyle(LibraryPressStyle())
            .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded { content.frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .modifier(MediaDetailPanel())
    }
}

struct MediaDetailCircleStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle).tint(Constants.brandTitlePink)
        } else {
            content.buttonStyle(MediaDetailMaterialButtonStyle()).tint(Constants.brandTitlePink)
        }
    }
}

struct MediaDetailActionIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).foregroundStyle(Constants.brandTitlePink).font(.title2).frame(width: 20, height: 20).padding(10)
    }
}

private struct MediaDetailMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// iOS 18 toolbars do not supply the glass backing that keeps dark labels readable.
struct MediaDetailToolbarStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.buttonStyle(MediaDetailToolbarButtonStyle())
        }
    }
}

private struct MediaDetailToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
