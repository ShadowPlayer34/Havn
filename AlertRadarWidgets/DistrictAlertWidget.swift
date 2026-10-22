import SwiftUI
import WidgetKit

// "My district" from option 3a: whether an alert stands over the district someone said
// they live in.
//
// Unlike the shelter widget this one reads the overlay itself. A shelter distance needs a
// fix only the app has; this needs nothing but the district and `/threats/zones`, which
// is the same payload for every client — and a widget that says "All clear" until its
// owner happens to open the app is the one thing it must not be. The app still writes
// the same state on every poll while it is open, and reloads this the moment it changes.

struct DistrictAlertEntry: TimelineEntry {
    let date: Date
    let reading: DistrictAlertReading

    /// Gallery and placeholder only — the design's own example.
    static var sample: DistrictAlertEntry {
        let now = Date.now
        let state = DistrictAlertState(
            district: .shevchenkivskyi,
            level: .alert,
            startedAt: now.addingTimeInterval(-23 * 60),
            endedAt: nil,
            checkedAt: now
        )
        return DistrictAlertEntry(
            date: now,
            reading: DistrictAlertReading(district: .shevchenkivskyi, state: state, now: now)
        )
    }
}

struct DistrictAlertProvider: TimelineProvider {
    /// How often the widget fetches on its own. WidgetKit rations reloads to a few dozen
    /// a day, so this is about as often as it will honour; the entries in between only
    /// count the minutes up.
    private static let refreshMinutes = 15

    func placeholder(in context: Context) -> DistrictAlertEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DistrictAlertEntry) -> Void) {
        guard !context.isPreview else {
            completion(.sample)
            return
        }
        completion(entry(at: .now, state: DistrictAlertStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DistrictAlertEntry>) -> Void) {
        Task {
            let state = await refresh()
            let now = Date.now
            // One entry a minute, so "23 min" counts up without spending a reload on each.
            let entries = (0..<Self.refreshMinutes).map {
                entry(at: now.addingTimeInterval(Double($0) * 60), state: state)
            }
            let next = now.addingTimeInterval(Double(Self.refreshMinutes) * 60)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }

    private func entry(at date: Date, state: DistrictAlertState?) -> DistrictAlertEntry {
        DistrictAlertEntry(
            date: date,
            reading: DistrictAlertReading(district: DistrictAlertStore.homeDistrict, state: state, now: date)
        )
    }

    /// Read the overlay and fold it into the shared state. On failure the last state stands
    /// — with its own `checkedAt`, so the tile turns amber rather than vouching for it.
    private func refresh() async -> DistrictAlertState? {
        guard let district = DistrictAlertStore.homeDistrict else { return nil }
        do {
            let zones = try await Self.zones()
            let now = Date.now
            let alert = district.alert(in: zones, at: now)
            return DistrictAlertStore.record(level: alert.level, earliestReport: alert.earliestReport, at: now)
        } catch {
            return DistrictAlertStore.load()
        }
    }

    /// One unconditional fetch: the extension is torn down between runs, so it has no
    /// ETag worth revalidating against.
    private static func zones() async throws -> [ThreatZone] {
        var request = URLRequest(url: ThreatAPI.baseURL.appending(path: ThreatAPI.zonesPath))
        request.setValue("application/geo+json, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ThreatAPI.zonesTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ThreatZoneCollection.self, from: data).zones
    }
}

struct DistrictAlertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DistrictAlertStore.kind, provider: DistrictAlertProvider()) { entry in
            DistrictAlertWidgetView(entry: entry)
        }
        .configurationDisplayName("My District")
        .description("Whether an alert is on in the district you live in.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct DistrictAlertWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DistrictAlertEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            DistrictAlertRectangular(reading: entry.reading)
                .containerBackground(for: .widget) { Color.clear }
        default:
            DistrictAlertTile(reading: entry.reading)
                .containerBackground(for: .widget) {
                    DistrictAlertTileBackground(reading: entry.reading)
                }
        }
    }
}
