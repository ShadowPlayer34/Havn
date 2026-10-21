import SwiftUI
import WidgetKit

// The two lock screen cards from option 1b, as real widgets.
//
// `NearestShelterWidget` runs on live data: the app writes the last `/shelters/nearest`
// answer into the shared App Group container and the timeline reads it back. The gauge
// below is still the design's sample — nothing in the API answers "how exposed is this
// exact spot", and inventing a percentage for a safety widget is the one thing worse
// than not shipping it.

// MARK: - Nearest shelter

struct ShelterEntry: TimelineEntry {
    let date: Date
    let shelter: WidgetSnapshot.NearestShelter?
    /// When the app received this answer. Nil when there has never been one.
    let capturedAt: Date?

    /// Only ever shown as the skeleton behind a loading widget and in the gallery, where
    /// the system expects something representative rather than something true.
    static let sample = ShelterEntry(
        date: .now,
        shelter: .init(
            name: "Metro Vokzalna", metres: 240, walkMinutes: 3, isAlwaysOpen: true, hours: nil
        ),
        capturedAt: .now
    )

    /// A distance measured from where the phone was an hour ago is not a distance.
    var isStale: Bool {
        guard let capturedAt else { return false }
        return Date.now.timeIntervalSince(capturedAt) > 3_600
    }
}

struct NearestShelterProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShelterEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ShelterEntry) -> Void) {
        completion(context.isPreview ? .sample : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShelterEntry>) -> Void) {
        // The app republishes whenever the answer actually changes and reloads this
        // timeline itself. The interval is only a backstop, so a widget on a phone whose
        // owner has not opened the app still re-renders and ages its own copy.
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func current() -> ShelterEntry {
        let snapshot = WidgetSnapshotStore.load()
        return ShelterEntry(
            date: .now, shelter: snapshot?.shelter, capturedAt: snapshot?.capturedAt
        )
    }
}

struct NearestShelterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSnapshotStore.nearestShelterKind, provider: NearestShelterProvider()
        ) { entry in
            NearestShelterWidgetView(entry: entry)
        }
        .configurationDisplayName("Nearest Shelter")
        .description("The closest safe haven, ranked by walking time.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct NearestShelterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShelterEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("NEAREST SHELTER")
                    .font(.system(size: 11, weight: .semibold))
                if let shelter = entry.shelter {
                    Text(shelter.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(detail(for: shelter))
                        .font(.system(size: 12))
                } else {
                    Text("No data yet")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Open AlertRadar once")
                        .font(.system(size: 12))
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("NEAREST SHELTER")
                    .font(VAFont.display(9.5))
                    .tracking(em: 0.1, size: 9.5)
                    .foregroundStyle(VA.secondary(0.45))

                if let shelter = entry.shelter {
                    Text(shelter.name)
                        .font(VAFont.display(17))
                        .tracking(em: -0.01, size: 17)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        // Register addresses run long. The street you are being sent to
                        // claims its two lines before the caption below, and shrinks
                        // rather than ending in an ellipsis.
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                    Text(distanceLabel(shelter.metres))
                        .font(VAFont.rounded(24))
                        // Amber, not green, once the distance is old enough to be wrong.
                        .foregroundStyle(entry.isStale ? VA.orange : VA.green)
                    Spacer(minLength: 0)
                    Text(detail(for: shelter))
                        .font(VAFont.display(11, .medium))
                        .foregroundStyle(VA.secondary(0.5))
                        .lineLimit(2)
                        // Whatever the address left it. "restricted" cut to "restrict…"
                        // is the one word here that has to arrive whole.
                        .minimumScaleFactor(0.8)
                } else {
                    Text("No data yet")
                        .font(VAFont.display(17))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("Open AlertRadar once so it can find the register entries near you.")
                        .font(VAFont.display(11, .medium))
                        .foregroundStyle(VA.secondary(0.5))
                        .lineHeight(1.3, size: 11)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { VA.card }
        }
    }

    /// "240 m" / "1.4 km" — the same wording the app uses for the same number.
    private func distanceLabel(_ metres: Int) -> String {
        metres < 1_000 ? "\(metres) m" : String(format: "%.1f km", Double(metres) / 1_000)
    }

    /// Says when the walk was measured rather than pretending it was measured now.
    private func detail(for shelter: WidgetSnapshot.NearestShelter) -> String {
        if entry.isStale, let capturedAt = entry.capturedAt {
            return "measured \(capturedAt.formatted(.relative(presentation: .numeric)))"
        }
        return "\(shelter.walkMinutes) min walk · \(opening(for: shelter))"
    }

    /// The register's hours field is free text: sometimes "08:00-20:00", sometimes a
    /// sentence about who is allowed through the door. Anything too long for the line
    /// becomes a short flag instead — cut off mid-word it reads as noise, and calling it
    /// open would be a lie about a door that is locked to you.
    private func opening(for shelter: WidgetSnapshot.NearestShelter) -> String {
        if shelter.isAlwaysOpen { return "open 24/7" }
        guard let hours = shelter.hours, hours.count <= 20 else { return "restricted" }
        return hours
    }
}

// MARK: - Location safety

/// Sample data, and knowingly so: see the note at the top of the file.
struct SafetyEntry: TimelineEntry {
    let date: Date
    let safetyPercent: Int
}

struct SampleSafetyProvider: TimelineProvider {
    private let sample = SafetyEntry(date: .now, safetyPercent: 88)

    func placeholder(in context: Context) -> SafetyEntry { sample }

    func getSnapshot(in context: Context, completion: @escaping (SafetyEntry) -> Void) {
        completion(sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SafetyEntry>) -> Void) {
        completion(Timeline(entries: [sample], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct SafetyGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.vectoralert.safety-gauge", provider: SampleSafetyProvider()) { entry in
            SafetyGaugeWidgetView(entry: entry)
        }
        .configurationDisplayName("Location Safety")
        .description("How exposed your precise location is to the current risk area.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct SafetyGaugeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SafetyEntry

    private var gauge: SafetyGauge { SafetyGauge.forPercent(entry.safetyPercent) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.safetyPercent), in: 0...100) {
                Text("SAFE")
            } currentValueLabel: {
                Text("\(entry.safetyPercent)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(spacing: 9) {
                SafetyGaugeRing(gauge: gauge, diameter: 82)
                Text(gauge.caption)
                    .font(VAFont.display(11, .medium))
                    .foregroundStyle(VA.secondary(0.55))
                    .multilineTextAlignment(.center)
                    .lineHeight(1.35, size: 11)
            }
            .padding(.horizontal, 8)
            .containerBackground(for: .widget) { VA.card }
        }
    }
}
