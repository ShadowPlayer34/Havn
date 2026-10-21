import ActivityKit
import SwiftUI
import WidgetKit

/// Option 1b, for real: the Live Activity you glance at without opening the app, and the
/// three Dynamic Island presentations behind it.
struct ThreatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThreatActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(VA.card.opacity(0.78))
                .activitySystemActionForegroundColor(VA.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.trailing) {
                    if let arrival = context.state.arrival {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(arrival.label)
                                .font(VAFont.rounded(22))
                                .foregroundStyle(VA.orange)
                            Text("to sector")
                                .font(VAFont.display(10, .medium))
                                .foregroundStyle(VA.secondary(0.45))
                        }
                    }
                }
                // Identity sits in .bottom: it is the only full-width region, and a real place
                // name never fits the narrow leading one.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.state.title)
                                .font(VAFont.display(15))
                                .foregroundStyle(.white)
                            Text(context.state.threat)
                                .font(VAFont.display(12, .medium))
                                .foregroundStyle(VA.secondary(0.55))
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // No bar when nothing is inbound: a full-width track at zero
                        // reads as a broken widget rather than a quiet sky.
                        if let arrival = context.state.arrival {
                            ThreatProgressTimer(range: arrival.progressRange, height: 6)
                        }
                        HStack(spacing: 10) {
                            if let percent = context.state.safetyPercent {
                                SafetyBadge(percent: percent)
                            }
                            Spacer(minLength: 0)
                            Text("updated \(context.state.updated, style: .relative) ago")
                                .font(VAFont.display(11.5, .medium))
                                .foregroundStyle(VA.secondary(0.45))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }
                }
            } compactLeading: {
                AppGlyph(width: 13, height: 15, dot: 5)
            } compactTrailing: {
                if let arrival = context.state.arrival {
                    Text(arrival.label)
                        .font(VAFont.rounded(14, .semibold))
                        .foregroundStyle(VA.orange)
                }
            } minimal: {
                AppGlyph(width: 12, height: 14, dot: 4.5)
            }
            .keylineTint(VA.red)
        }
    }
}

/// The lock screen banner from the design: mark, name, window, one line of fact, progress.
struct LockScreenActivityView: View {
    let context: ActivityViewContext<ThreatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppGlyph(width: 22, height: 24, dot: 8)
                Text("VectorAlert")
                    .font(VAFont.display(14))
                    .foregroundStyle(.white)
                Text("now")
                    .font(VAFont.display(12, .medium))
                    .foregroundStyle(VA.secondary(0.45))
                Spacer(minLength: 0)
                if let arrival = context.state.arrival {
                    Text(arrival.label)
                        .font(VAFont.rounded(20))
                        .foregroundStyle(VA.orange)
                }
            }

            // Two lines rather than one run-on: the place is only named when it is known,
            // and the status has to stand on its own when it is not.
            VStack(alignment: .leading, spacing: 3) {
                if let area = context.state.area {
                    Text(area)
                        .font(VAFont.display(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(context.state.status)
                    .font(VAFont.display(14, .regular))
                    .lineHeight(1.35, size: 14)
                    .foregroundStyle(VA.secondary(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let arrival = context.state.arrival {
                ThreatProgressTimer(range: arrival.progressRange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }
}

/// Only drawn when a percentage is actually supplied. Nothing in the API answers
/// "how safe is this spot", so the app currently sends none — see `ThreatActivityState`.
struct SafetyBadge: View {
    let percent: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(VA.green).frame(width: 6, height: 6)
            Text("Location Safety: \(percent)%")
                .font(VAFont.display(11.5))
                .foregroundStyle(VA.green)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(VA.green.opacity(0.16)))
        .overlay(Capsule().strokeBorder(VA.green.opacity(0.3), lineWidth: 1))
    }
}
