import UIKit

enum PreviewSampleData {
    static var sampleItems: [MediaItem] {
        let poster = generatePosterData()
        return [
            MediaItem(
                title: "千与千寻",
                poster: poster,
                status: .watched,
                watchedAt: YearMonth(year: 2024, month: 3),
                rating: 10,
                review: "每次看都有新发现",
                playURL: "https://example.com/spirited-away"),
            MediaItem(
                title: "星际穿越",
                poster: poster,
                status: .watched,
                watchedAt: YearMonth(year: 2024, month: 3),
                rating: 9,
                review: nil,
                playURL: nil),
            MediaItem(
                title: "你想活出怎样的人生",
                poster: poster,
                status: .watched,
                watchedAt: YearMonth(year: 2024, month: 1),
                rating: 8,
                review: nil,
                playURL: "https://example.com/boy-and-heron"),
            MediaItem(
                title: "沙丘2",
                poster: nil,
                status: .watching,
                watchedAt: YearMonth(year: 2025, month: 8),
                rating: 0,
                review: nil,
                playURL: nil),
            MediaItem(
                title: "阿诺拉",
                poster: poster,
                status: .wantToWatch,
                rating: 0,
                review: nil,
                playURL: nil),
            MediaItem(
                title: "野生机器人",
                poster: nil,
                status: .wantToWatch,
                rating: 0,
                review: nil,
                playURL: nil)
        ]
    }

    private static func generatePosterData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 150))
        let image = renderer.image { context in
            UIColor(Constants.accentPink).setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 100, height: 150)))
            UIColor.white.withAlphaComponent(0.4).setFill()
            let circle = CGRect(x: 30, y: 45, width: 40, height: 40)
            context.cgContext.fillEllipse(in: circle)
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
