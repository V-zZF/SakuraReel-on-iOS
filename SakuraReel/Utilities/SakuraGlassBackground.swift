import SwiftUI

struct SakuraGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(Constants.accentPink)
                        .glassEffect(.regular.tint(Constants.accentPink), in: shape)
                }
        } else {
            content
                .background {
                    shape.fill(Constants.accentPink)
                }
        }
    }
}

extension View {
    func sakuraGlassBackground<S: Shape>(shape: S) -> some View {
        modifier(SakuraGlassBackground(shape: shape))
    }
}
