import SwiftUI

struct TimeMachineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let moments: [TimeMachineMoments.Moment]
    private let onClose: () -> Void

    @State private var selectedQuarterID: TimeMachineMoments.Quarter?
    @State private var activeQuarterID: TimeMachineMoments.Quarter?
    @State private var selectedItemID: UUID?
    @State private var showsReviewBack = false
    @State private var detailSpread: CGFloat = 1
    @State private var isReturningToQuarters = false
    @Namespace private var heroNamespace

    init(items: [MediaItem], rankingOrder: [UUID]? = nil, onClose: @escaping () -> Void = {}) {
        let preparedMoments = TimeMachineMoments.moments(from: items, rankingOrder: rankingOrder)
        moments = preparedMoments
        self.onClose = onClose
        _selectedQuarterID = State(initialValue: TimeMachineMoments.openingQuarter(in: preparedMoments, today: .now))
    }

    private var activeMoment: TimeMachineMoments.Moment? {
        moments.first { $0.id == activeQuarterID }
    }

    var body: some View {
        GeometryReader { geometry in
            let headerTopInset = UIDevice.current.userInterfaceIdiom == .phone
                ? max(geometry.safeAreaInsets.top, 60)
                : max(geometry.safeAreaInsets.top, 12)
            let footerHeight = min(activeMoment == nil ? 105 : 155, geometry.size.height * 0.24)
            let stageHeight = max(0, min(
                geometry.size.height * 0.68,
                760,
                geometry.size.height - headerTopInset - 54 - footerHeight - 12
            ))
            VStack(spacing: 0) {
                header
                    .padding(.top, headerTopInset)

                if let moment = activeMoment {
                    Spacer(minLength: 0)
                    detailStage(moment)
                        .frame(width: geometry.size.width, height: stageHeight)
                        .id(geometry.size)
                        .allowsHitTesting(!isReturningToQuarters)
                    detailFooter(moment)
                        .frame(height: footerHeight)
                        .opacity(reduceMotion ? 1 : detailSpread)
                    Spacer(minLength: 0)
                } else if moments.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                    quarterStage
                        .frame(width: geometry.size.width, height: stageHeight)
                        .id(geometry.size)
                    quarterFooter
                        .frame(height: footerHeight)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                ZStack {
                    Color(red: 0.025, green: 0.025, blue: 0.035)
                    RadialGradient(
                        colors: [.white.opacity(0.08), .clear],
                        center: .init(x: 0.5, y: 0.43),
                        startRadius: 16,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.7
                    )
                }
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: selectedQuarterID)
        .sensoryFeedback(.selection, trigger: selectedItemID)
        .onChange(of: selectedItemID) { _, _ in showsReviewBack = false }
    }

    private func returnToQuarters() {
        guard let quarter = activeQuarterID, !isReturningToQuarters else { return }
        guard !reduceMotion else {
            activeQuarterID = nil
            showsReviewBack = false
            detailSpread = 1
            return
        }

        isReturningToQuarters = true
        withAnimation(.easeInOut(duration: 0.34)) {
            showsReviewBack = false
            detailSpread = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled,
                  isReturningToQuarters,
                  activeQuarterID == quarter else { return }
            withAnimation(.easeInOut(duration: 0.52)) {
                activeQuarterID = nil
            }
            try? await Task.sleep(for: .milliseconds(520))
            detailSpread = 1
            isReturningToQuarters = false
        }
    }

    private var header: some View {
        HStack {
            if activeQuarterID != nil {
                Button(action: returnToQuarters) {
                    Label("返回季度", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("返回季度")
                .disabled(isReturningToQuarters)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()
            Text(activeQuarterID?.title ?? "时光机")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .lineLimit(1)
            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("关闭时光机")
            .disabled(isReturningToQuarters)
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private var quarterStage: some View {
        CoverFlowStage(
            items: moments,
            selectedID: $selectedQuarterID,
            reduceMotion: reduceMotion,
            animateDragEnd: false,
            captionHeight: 52,
            spreadProgress: 1,
            collapsingToHero: false,
            heroID: selectedQuarterID,
            heroNamespace: heroNamespace,
            heroIsSource: true,
            selectedHint: { _ in "打开季度" },
            accessibilityText: { "\($0.quarter.title)，\($0.count) 部作品" },
            artwork: { SquareMemoryPoster(item: $0.representative) },
            caption: { moment in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(String(moment.quarter.year)) 年")
                        .foregroundStyle(.white.opacity(0.88))
                    Text(moment.quarter.season)
                        .foregroundStyle(seasonColor(for: moment.quarter))
                }
                .font(.system(selectedQuarterID == moment.id ? .title2 : .headline,
                              design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 12)
            },
            onActivate: { moment in
                selectedItemID = moment.representative.id
                showsReviewBack = false
                isReturningToQuarters = false
                detailSpread = reduceMotion ? 1 : 0
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.54)) {
                    activeQuarterID = moment.id
                }
                guard !reduceMotion else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(65))
                    guard !Task.isCancelled,
                          !isReturningToQuarters,
                          activeQuarterID == moment.id else { return }
                    withAnimation(.spring(response: 0.56, dampingFraction: 0.86)) {
                        detailSpread = 1
                    }
                }
            }
        )
        .accessibilityIdentifier("timeMachineQuarters")
    }

    private var quarterFooter: some View {
        VStack(spacing: 5) {
            if let moment = moments.first(where: { $0.id == selectedQuarterID }) {
                Text(moment.quarter.monthRange)
                    .font(.system(.headline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(moment.count) 部作品")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private func detailStage(_ moment: TimeMachineMoments.Moment) -> some View {
        CoverFlowStage(
            items: TimeMachineMoments.centerOut(moment.rankedItems),
            selectedID: $selectedItemID,
            reduceMotion: reduceMotion,
            animateDragEnd: true,
            captionHeight: 0,
            spreadProgress: detailSpread,
            collapsingToHero: isReturningToQuarters,
            heroID: moment.representative.id,
            heroNamespace: heroNamespace,
            heroIsSource: false,
            selectedHint: { item in
                item.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? "翻面查看短评"
                    : "没有短评"
            },
            accessibilityText: { item in
                "\(item.title)，\(item.rating == 0 ? "未评分" : "\(item.rating) 分")"
            },
            artwork: { item in
                MemoryFlipArtwork(
                    item: item,
                    review: item.review ?? "",
                    isFlipped: selectedItemID == item.id && showsReviewBack
                )
            },
            caption: { _ in EmptyView() },
            onActivate: { item in
                guard item.review?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.48)) {
                    showsReviewBack.toggle()
                }
            }
        )
        .accessibilityIdentifier("timeMachineItems")
    }

    private func detailFooter(_ moment: TimeMachineMoments.Moment) -> some View {
        VStack(spacing: 12) {
            Text("本季看过 \(moment.count) 部")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .accessibilityIdentifier("timeMachineCount")

            if let item = moment.rankedItems.first(where: { $0.id == selectedItemID }) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        Text("\(String(item.watchYear ?? moment.quarter.year)) 年 \(String(item.watchMonth ?? 1)) 月")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    Spacer(minLength: 6)
                    Text(item.rating == 0 ? "未评分" : "\(item.rating) 分")
                        .font(.system(item.rating == 0 ? .title3 : .largeTitle,
                                      design: .rounded, weight: .bold))
                        .foregroundStyle(RatingColor.color(for: item.rating))
                }
                .padding(16)
                .frame(maxWidth: 520)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                .id(item.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func seasonColor(for quarter: TimeMachineMoments.Quarter) -> Color {
        switch quarter.number {
        case 1: Color(red: 0.51, green: 0.74, blue: 0.95)
        case 2: Color(red: 0.97, green: 0.62, blue: 0.72)
        case 3: Color(red: 0.54, green: 0.79, blue: 0.60)
        default: Color(red: 0.95, green: 0.75, blue: 0.42)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.58))
            Text("还没有可以回看的季度")
                .font(.headline)
            Text("为看过的作品填写观看年月后，回忆会出现在这里。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .accessibilityIdentifier("timeMachineEmpty")
    }
}

private struct SquareMemoryPoster: View {
    @Environment(MediaRepository.self) private var repository
    let item: MediaItem
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(red: 0.22, green: 0.18, blue: 0.22))
                    .overlay {
                        Image(systemName: "film.fill")
                            .font(.system(size: min(geometry.size.width * 0.22, 48)))
                            .foregroundStyle(.white.opacity(0.32))
                    }
            }
        }
        .task(id: repository.document.revision) {
            var data = item.poster
            if data == nil { data = await repository.attachment(.poster, for: item.id) }
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

private struct MemoryFlipArtwork: View {
    let item: MediaItem
    let review: String
    let isFlipped: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SquareMemoryPoster(item: item)
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(
                        .degrees(isFlipped ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.8
                    )

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    ScrollView {
                        Text(review)
                            .font(.system(.title3, design: .serif, weight: .medium))
                            .foregroundStyle(.white.opacity(0.96))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(geometry.size.width * 0.09)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .background {
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.14, blue: 0.18),
                            Color(red: 0.09, green: 0.08, blue: 0.11),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.8
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isFlipped ? "短评：\(review)" : "海报")
    }
}

/// Full-screen stage slides down from the top edge on every device.
struct TimeMachinePortal: View {
    let items: [MediaItem]
    let rankingOrder: [UUID]
    let reduceMotion: Bool
    let onDismiss: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isClosing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(progress * 0.18)
                    .contentShape(Rectangle())

                machine(size: geometry.size)
                    .offset(y: (progress - 1) * (geometry.size.height + 24))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.spring(response: 0.64, dampingFraction: 0.9)) {
                    progress = 1
                }
            }
        }
    }

    private func machine(size: CGSize) -> some View {
        TimeMachineView(items: items, rankingOrder: rankingOrder, onClose: close)
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(progress >= 0.999 && !isClosing)
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        guard !reduceMotion else {
            onDismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.36)) {
            progress = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            onDismiss()
        }
    }
}

#Preview {
    TimeMachineView(items: PreviewSampleData.sampleItems)
        .environment(MediaRepository(seedItems: PreviewSampleData.sampleItems))
}
