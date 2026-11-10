import WidgetKit
import SwiftUI

// Home Screen widget: the app icon's d-pad at small, medium and large sizes.
// Tapping it opens the app.

struct RemoteEntry: TimelineEntry { let date: Date }

struct RemoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemoteEntry { RemoteEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (RemoteEntry) -> Void) {
        completion(RemoteEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RemoteEntry>) -> Void) {
        completion(Timeline(entries: [RemoteEntry(date: Date())], policy: .never))
    }
}

private let rim = LinearGradient(colors: [Color(red: 0.59, green: 0.27, blue: 0.90), Color(red: 0.16, green: 0.43, blue: 1.0)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)

struct DPadArt: View {
    private let chevrons: [(String, CGFloat, CGFloat)] = [
        ("chevron.up", 0, -1), ("chevron.right", 1, 0), ("chevron.down", 0, 1), ("chevron.left", -1, 0)
    ]
    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(rim, lineWidth: max(1.5, s * 0.014))
                ForEach(0..<chevrons.count, id: \.self) { i in
                    Image(systemName: chevrons[i].0)
                        .font(.system(size: s * 0.11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.85))
                        .offset(x: chevrons[i].1 * s * 0.33, y: chevrons[i].2 * s * 0.33)
                }
                Circle().fill(Color(white: 0.19))
                    .overlay(Circle().strokeBorder(rim, lineWidth: max(2, s * 0.022)))
                    .shadow(color: .black.opacity(0.5), radius: s * 0.03, y: s * 0.02)
                    .frame(width: s * 0.32, height: s * 0.32)
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemoteEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 18) {
                DPadArt()
                VStack(alignment: .leading, spacing: 4) {
                    Text("My TV Remote").font(.headline).foregroundStyle(.white)
                    Text("Tap to open").font(.caption).foregroundStyle(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            DPadArt()
        }
    }
}

@main
struct RemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RemoteWidget", provider: RemoteProvider()) { entry in
            RemoteWidgetView(entry: entry)
        }
        .configurationDisplayName("My TV Remote")
        .description("Open your TV remote.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
