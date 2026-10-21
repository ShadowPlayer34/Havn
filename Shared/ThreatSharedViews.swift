import SwiftUI

// The pieces the app's previews and the real system surfaces both draw.

/// Progress bar shared by the map cluster, the Live Activity and the Dynamic Island.
struct ThreatProgressBar: View {
    var progress: Double
    var height: CGFloat = 5
    var track: Double = 0.14

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(track))
                Capsule()
                    .fill(LinearGradient(colors: [VA.orange, VA.red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// The same bar, ticking on its own between activity updates.
struct ThreatProgressTimer: View {
    var range: ClosedRange<Date>
    var height: CGFloat = 5

    var body: some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(VA.orange)
        .frame(height: height)
    }
}

/// The app's mark: a blunt-nosed body, no siren, no crosshair.
struct AppGlyph: View {
    var width: CGFloat
    var height: CGFloat
    var dot: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: width * 0.21,
            bottomLeadingRadius: width * 0.47,
            bottomTrailingRadius: width * 0.47,
            topTrailingRadius: width * 0.21
        )
        .fill(VA.red)
        .frame(width: width, height: height)
        .overlay(
            Circle()
                .fill(VA.card.opacity(0.6))
                .frame(width: dot, height: dot)
        )
    }
}

/// Lock screen gauge states, cycled by tapping the widget preview.
struct SafetyGauge {
    let value: String
    let state: String
    let color: Color
    let degrees: Double
    let caption: String

    static let all: [SafetyGauge] = [
        SafetyGauge(value: "88%", state: "SAFE", color: VA.green, degrees: 317, caption: "Outside main risk area"),
        SafetyGauge(value: "54%", state: "WATCH", color: VA.orange, degrees: 194, caption: "Risk area edge · widening"),
        SafetyGauge(value: "21%", state: "SEEK COVER", color: VA.red, degrees: 76, caption: "Inside risk area · 2–6 min")
    ]

    static func forPercent(_ percent: Int) -> SafetyGauge {
        switch percent {
        case 70...: all[0]
        case 40..<70: all[1]
        default: all[2]
        }
    }
}

/// Conic gauge: starts at the bottom, sweeps clockwise.
struct SafetyGaugeRing: View {
    let gauge: SafetyGauge
    var diameter: CGFloat = 82

    private var ring: CGFloat { diameter * 0.094 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: ring)
                .frame(width: diameter - ring, height: diameter - ring)
            Circle()
                .trim(from: 0, to: gauge.degrees / 360)
                .stroke(gauge.color, style: StrokeStyle(lineWidth: ring))
                .frame(width: diameter - ring, height: diameter - ring)
                .rotationEffect(.degrees(90))
            VStack(spacing: 1) {
                Text(gauge.value)
                    .font(VAFont.rounded(diameter * 0.268))
                    .foregroundStyle(.white)
                Text(gauge.state)
                    .font(VAFont.display(diameter * 0.104))
                    .tracking(em: 0.1, size: diameter * 0.104)
                    .foregroundStyle(gauge.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
