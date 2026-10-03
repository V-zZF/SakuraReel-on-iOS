import SwiftUI

private struct PopupDismissKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    fileprivate var popupDismiss: (@MainActor () -> Void)? {
        get { self[PopupDismissKey.self] }
        set { self[PopupDismissKey.self] = newValue }
    }
}

/// Fall back to native dismissal outside a library-managed sheet.
struct LibraryPopupDismiss: DynamicProperty {
    @Environment(\.dismiss) private var nativeDismiss
    @Environment(\.popupDismiss) private var popupDismiss

    @MainActor func callAsFunction() {
        if let popupDismiss { popupDismiss() } else { nativeDismiss() }
    }
}

private struct PopupFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let close: @MainActor () -> Void
    @State private var visible = false
    @State private var closing = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || visible ? 1 : 0)
            .allowsHitTesting(!closing)
            .environment(\.popupDismiss, {
                guard !closing else { return }
                closing = true
                guard !reduceMotion else { close(); return }
                withAnimation(.easeOut(duration: 0.16)) { visible = false }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(160))
                    close()
                }
            })
            .task {
                guard !visible, !closing else { return }
                await Task.yield()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { visible = true }
            }
    }
}

extension View {
    func librarySheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().modifier(PopupFade(close: { isPresented.wrappedValue = false }))
        }
    }

    func librarySheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { selection in
            content(selection).modifier(PopupFade(close: { item.wrappedValue = nil }))
        }
    }
}

enum Constants {
    static let brandTitlePink = Color(hex: "E07894")
    static let accentPink = brandTitlePink
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

/// Reserve the same footer height whether rating, date or an action is missing.
struct LibraryCardFooter: ViewModifier {
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}

/// Two lines determine the slot height; shorter titles are vertically centered.
struct LibraryCardTitle: View {
    let title: String

    var body: some View {
        ZStack(alignment: .leading) {
            Text("占位\n占位")
                .lineLimit(2, reservesSpace: true)
                .hidden()
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
