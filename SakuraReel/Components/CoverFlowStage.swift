import SwiftUI

/// 两层时光机共用的 Cover Flow 舞台。输入顺序就是从左到右的物理位置。
struct CoverFlowStage<Item: Identifiable, Artwork: View, Caption: View>: View where Item.ID: Hashable {
    let items: [Item]
    @Binding var selectedID: Item.ID?
    let reduceMotion: Bool
    let animateDragEnd: Bool
    let captionHeight: CGFloat
    let spreadProgress: CGFloat
    let collapsingToHero: Bool
    let heroID: Item.ID?
    let heroNamespace: Namespace.ID?
    let heroIsSource: Bool
    let selectedHint: (Item) -> String
    let accessibilityText: (Item) -> String
    @ViewBuilder let artwork: (Item) -> Artwork
    @ViewBuilder let caption: (Item) -> Caption
    let onActivate: (Item) -> Void

    @State private var dragTranslation: CGFloat = 0
    @State private var suppressActivationUntil = Date.distantPast

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedID } ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width * 0.58, max(0, geometry.size.height - captionHeight) * 0.55, 360)
            let step = max(side * 0.6, 1)
            let position = min(max(
                CGFloat(selectedIndex) - (reduceMotion ? 0 : dragTranslation / step), 0
            ), CGFloat(max(items.count - 1, 0)))

            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.19), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .offset(y: side * 0.34)
                    .accessibilityHidden(true)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let distance = CGFloat(index) - position
                    if abs(distance) < 4.4 || (collapsingToHero && item.id == heroID) {
                        let animatedDistance = distance * spreadProgress
                        let staysVisible = collapsingToHero
                            ? item.id == heroID
                            : item.id == selectedID
                        flowCard(item, side: side)
                            .scaleEffect(scale(for: animatedDistance))
                            .rotation3DEffect(
                                .degrees(Double(-52 * min(max(animatedDistance, -1), 1))),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.7
                            )
                            .offset(x: offset(for: animatedDistance, side: side))
                            .opacity(
                                max(0, 1 - max(abs(animatedDistance) - 2, 0) * 0.14)
                                * (staysVisible ? 1 : spreadProgress)
                            )
                            .zIndex(
                                10 - Double(abs(distance))
                                + (collapsingToHero && item.id == heroID ? Double(1 - spreadProgress) * 20 : 0)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Observe drags over the buttons as well as the empty stage.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        suppressActivationUntil = Date.now.addingTimeInterval(0.15)
                        dragTranslation = value.translation.width
                    }
                    .onEnded { value in
                        // A button can also receive the release of a simultaneous drag.
                        // Ignore that release so it cannot reselect the card we started on.
                        if abs(value.translation.width) > abs(value.translation.height) {
                            suppressActivationUntil = Date.now.addingTimeInterval(0.15)
                        }
                        guard !items.isEmpty,
                              abs(value.translation.width) > abs(value.translation.height) else {
                            dragTranslation = 0
                            return
                        }
                        let currentPosition = CGFloat(selectedIndex) - value.translation.width / step
                        let next = min(max(Int(currentPosition.rounded()), 0), items.count - 1)
                        if animateDragEnd && !reduceMotion {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                selectedID = items[next].id
                                dragTranslation = 0
                            }
                        } else {
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                selectedID = items[next].id
                                dragTranslation = 0
                            }
                        }
                    }
            )
            .accessibilityAction(named: Text("上一张")) { moveSelection(by: -1) }
            .accessibilityAction(named: Text("下一张")) { moveSelection(by: 1) }
        }
    }

    private func flowCard(_ item: Item, side: CGFloat) -> some View {
        Button {
            guard Date.now >= suppressActivationUntil else { return }
            if selectedID == item.id {
                onActivate(item)
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)) {
                    selectedID = item.id
                }
            }
        } label: {
            VStack(spacing: 0) {
                caption(item)
                    .frame(width: side, height: captionHeight, alignment: .bottom)

                frontArtwork(item, side: side)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 8)

                artwork(item)
                    .frame(width: side, height: side)
                    .clipped()
                    .scaleEffect(y: -1)
                    .frame(width: side, height: side * 0.32, alignment: .top)
                    .clipped()
                    .mask {
                        LinearGradient(
                            colors: [.white.opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .accessibilityHidden(true)
            }
            .frame(width: side, height: captionHeight + side * 1.32, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(item))
        .accessibilityValue(selectedID == item.id ? "中央" : "侧面")
        .accessibilityHint(selectedID == item.id ? selectedHint(item) : "移到中央")
        .accessibilityAction(named: Text("上一张")) { moveSelection(by: -1) }
        .accessibilityAction(named: Text("下一张")) { moveSelection(by: 1) }
    }

    @ViewBuilder
    private func frontArtwork(_ item: Item, side: CGFloat) -> some View {
        let cover = artwork(item)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        if item.id == heroID, let heroNamespace {
            cover.matchedGeometryEffect(id: "timeMachineHero", in: heroNamespace, isSource: heroIsSource)
        } else {
            cover
        }
    }

    private func moveSelection(by amount: Int) {
        guard !items.isEmpty else { return }
        let next = min(max(selectedIndex + amount, 0), items.count - 1)
        guard next != selectedIndex else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)) {
            selectedID = items[next].id
        }
    }

    private func offset(for distance: CGFloat, side: CGFloat) -> CGFloat {
        let magnitude = abs(distance)
        let shift = magnitude <= 1 ? magnitude * 0.68 : 0.68 + (magnitude - 1) * 0.27
        return (distance < 0 ? -1 : 1) * shift * side
    }

    private func scale(for distance: CGFloat) -> CGFloat {
        let magnitude = abs(distance)
        return max(0.63, 1 - min(magnitude, 1) * 0.22 - max(magnitude - 1, 0) * 0.035)
    }
}
