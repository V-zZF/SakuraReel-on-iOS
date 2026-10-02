import SwiftUI

enum Constants {
    static let accentPink = Color(hex: "F8A5B6")
    static let brandTitlePink = Color(hex: "C84F70")
    static let cardCornerRadius: CGFloat = 16
    static let cardShadowRadius: CGFloat = 10
    static let libraryBackground = Color(hex: "F5F4F3")
    /// 网格列间距与两侧留白。唯一来源在 `GridColumns`（那边不 import SwiftUI，模型测试读得到）
    static let gridSpacing: CGFloat = GridColumns.spacing
    static let posterAspectRatio: CGFloat = 2.0 / 3.0

    /// 海报从「没有」变成「有」时的淡入时长
    static let posterFadeInDuration: Double = 0.22

    /// 拖动中的源卡片 / 源行的透明度（抬起态：留在原位变淡，拖影跟着手指走）
    static let draggedCardOpacity: CGFloat = 0.4
}

/// Shared surfaces retain the ranking card's proportional sizing.
struct LibraryCardSurface: ViewModifier {
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Constants.cardCornerRadius * scale, style: .continuous)
                    .strokeBorder(.black.opacity(0.035), lineWidth: 0.5 * scale)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.07), radius: Constants.cardShadowRadius * scale, x: 0, y: 5 * scale)
            .shadow(color: .black.opacity(0.035), radius: 1 * scale, x: 0, y: 1 * scale)
    }
}

/// Native Button press state; no competing drag or tap recognizers.
struct LibraryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration.isPressed)
    }
}

/// Only rows visible when the ranking page opens take part in its one-time entrance.
struct RankingEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let enabled: Bool
    let hasEntered: Bool

    func body(content: Content) -> some View {
        content
            .opacity(enabled && !reduceMotion && !hasEntered ? 0 : 1)
            .offset(x: enabled && !reduceMotion && !hasEntered ? 24 : 0, y: 0)
            .animation(
                enabled && !reduceMotion
                    ? .easeOut(duration: 0.64).delay(Double(index) * 0.08)
                    : nil,
                value: hasEntered
            )
    }
}

struct LibraryInteractionFeedback: ViewModifier {
    let isSorting: Bool
    let editingID: String?
    let draggedID: UUID?
    let blockedMessage: String?
    let draftIDs: [UUID]

    func body(content: Content) -> some View {
        let navigation = content
            .sensoryFeedback(.selection, trigger: isSorting)
            .sensoryFeedback(.impact(weight: .light), trigger: editingID) { _, target in target != nil }
        let drag = navigation
            .sensoryFeedback(.impact(weight: .medium), trigger: draggedID) { _, target in target != nil }
            .sensoryFeedback(.warning, trigger: blockedMessage) { _, message in message != nil }
        return drag
            .sensoryFeedback(.selection, trigger: draftIDs) { old, new in
                draggedID != nil && old.count == new.count && old != new
            }
    }
}
