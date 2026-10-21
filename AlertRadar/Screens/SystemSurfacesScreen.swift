import SwiftUI

/// Option 1b — the surfaces you glance at without opening the app.
///
/// Everything below the Start button is a *drawing* of the design, run off the design
/// document's own looping countdown. The real Live Activity is the one that button
/// requests, and it is fed from the live threat data — see `ThreatActivityState`.
struct SystemSurfacesScreen: View {
    @Environment(ThreatModel.self) private var model
    @Environment(LiveActivityController.self) private var liveActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - 40

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    liveActivityControl

                    section("DYNAMIC ISLAND · COMPACT") {
                        CompactIslandMockup(label: model.islandLabel)
                    }

                    section("DYNAMIC ISLAND · EXPANDED") {
                        ExpandedIslandMockup()
                    }

                    section("LOCK SCREEN · LIVE ACTIVITY + INTERACTIVE WIDGET") {
                        LockScreenMockup()
                            .frame(width: 402, height: 572)
                            .scaleEffect(min(1, available / 402), anchor: .topLeading)
                            .frame(
                                width: available,
                                height: 572 * min(1, available / 402),
                                alignment: .topLeading
                            )
                    }
                }
                .padding(20)
            }
        }
        .background(Color(hex: 0x0B0B0C).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("System Integrations")
                .font(VAFont.title)
                .tracking(em: -0.02, size: 24)
                .foregroundStyle(.white)
            Spacer()
            Button("Done") { dismiss() }
                .font(VAFont.display(15))
                .foregroundStyle(VA.cyan)
                .buttonStyle(.plain)
        }
    }

    /// The previews below are drawings; this runs the real thing.
    private var liveActivityControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(liveActivity.isRunning ? "End Live Activity" : "Start Live Activity") {
                    if liveActivity.isRunning {
                        liveActivity.end()
                    } else {
                        // Starts from the reading the map has already fed in, so the
                        // activity opens saying what the map says.
                        liveActivity.start()
                    }
                }
                .font(VAFont.display(15))
                .buttonStyle(.glassProminent)
                .tint(liveActivity.isRunning ? VA.red : VA.cyan)
                .foregroundStyle(liveActivity.isRunning ? .white : VA.cyanInk)

                if liveActivity.isRunning {
                    StatusPill(dot: VA.green, blinkDuration: 2,
                               tint: VA.green.opacity(0.16), stroke: VA.green.opacity(0.32)) {
                        Text("On lock screen")
                            .font(VAFont.display(12))
                            .foregroundStyle(VA.green)
                    }
                }
                Spacer(minLength: 0)
            }

            if let error = liveActivity.lastError {
                Text(error)
                    .font(VAFont.display(11.5, .regular))
                    .foregroundStyle(VA.orangeText)
            } else {
                Text("Lock the device to see it, or press and hold the Dynamic Island.")
                    .font(VAFont.display(11.5, .regular))
                    .foregroundStyle(VA.secondary(0.45))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.12, size: 10)
                .foregroundStyle(VA.secondary(0.4))
            content()
        }
    }
}

// MARK: - Dynamic Island

struct CompactIslandMockup: View {
    let label: String

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 24)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x151A22), Color(hex: 0x0B0D11)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 24)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                )

            HStack(spacing: 9) {
                AppGlyph(width: 19, height: 21, dot: 7)
                Color.clear.frame(width: 44, height: 1)
                Text(label)
                    .font(VAFont.rounded(14, .semibold))
                    .foregroundStyle(VA.orange)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 126, minHeight: 37)
            .background(Capsule().fill(.black))
            .padding(.top, 11)
        }
        .frame(height: 118)
        .overlay(alignment: .topLeading) {
            Text("9:41")
                .font(VAFont.display(13))
                .foregroundStyle(VA.secondary(0.5))
                .padding(.leading, 18)
                .padding(.top, 60)
        }
        .overlay(alignment: .topTrailing) {
            Text("Tap and hold to expand")
                .font(VAFont.display(11, .medium))
                .foregroundStyle(VA.secondary(0.3))
                .padding(.trailing, 18)
                .padding(.top, 60)
        }
    }
}

struct ExpandedIslandMockup: View {
    @Environment(ThreatModel.self) private var model

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 12) {
                MapThumbnail()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Risk Area: Kyiv Region")
                        .font(VAFont.display(15))
                        .foregroundStyle(.white)
                    Text("Shahed-136 · area estimate")
                        .font(VAFont.display(12, .medium))
                        .foregroundStyle(VA.secondary(0.55))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.etaShort)
                        .font(VAFont.rounded(22))
                        .foregroundStyle(VA.orange)
                        .contentTransition(.numericText())
                    Text("to sector")
                        .font(VAFont.display(10, .medium))
                        .foregroundStyle(VA.secondary(0.45))
                }
            }

            ThreatProgressBar(progress: model.progress, height: 6, track: 0.12)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(VA.green).frame(width: 6, height: 6)
                    Text("Precise Location Safety: 88%")
                        .font(VAFont.display(11.5))
                        .foregroundStyle(VA.green)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(VA.green.opacity(0.16)))
                .overlay(Capsule().strokeBorder(VA.green.opacity(0.3), lineWidth: 1))

                Spacer(minLength: 0)

                Text("updated 4s ago")
                    .font(VAFont.display(11.5, .medium))
                    .foregroundStyle(VA.secondary(0.45))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 42).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 42).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

/// 44pt map tile: the same grid and the same heat blob, shrunk.
struct MapThumbnail: View {
    var body: some View {
        ZStack {
            Color(hex: 0x141416)
            Canvas { context, size in
                var x: CGFloat = 0
                while x <= size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.09)))
                    x += 11
                }
                var y: CGFloat = 0
                while y <= size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.09)))
                    y += 11
                }
            }
            MapBlob(
                stops: [
                    .init(color: Color(hex: 0xFF5032, opacity: 0.85), location: 0),
                    .init(color: Color(hex: 0xFF9500, opacity: 0.2), location: 0.55),
                    .init(color: .clear, location: 1)
                ],
                size: CGSize(width: 40, height: 36),
                rotation: 0,
                blur: 4
            )
            .position(x: 24, y: 20)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Lock screen

struct LockScreenMockup: View {
    @Environment(ThreatModel.self) private var model

    var body: some View {
        DesignCanvas(width: 402, height: 572) {
            Ellipse()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x101820), location: 0),
                        .init(color: .black, location: 0.6)
                    ],
                    center: .center, startRadius: 0, endRadius: 482
                ))
                .frame(width: 964, height: 915)
                .offset(x: -281, y: -457)

            Capsule()
                .fill(.black)
                .frame(width: 126, height: 34)
                .frame(width: 402, alignment: .center)
                .offset(y: 10)

            VStack(spacing: 0) {
                Text("Saturday, 15 August")
                    .font(VAFont.display(15, .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("14:32")
                    .font(.system(size: 78, weight: .light))
                    .tracking(em: -0.02, size: 78)
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .frame(width: 402)
            .offset(y: 64)

            HStack(spacing: 12) {
                gaugeWidget
                shelterWidget
            }
            .frame(width: 402 - 32)
            .offset(x: 16, y: 196)

            liveActivityBanner
                .frame(width: 402 - 32)
                .offset(x: 16, y: 400)

            Capsule()
                .fill(.white.opacity(0.6))
                .frame(width: 139, height: 5)
                .frame(width: 402, alignment: .center)
                .offset(y: 572 - 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var gaugeWidget: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.cycleGauge() }
        } label: {
            VStack(spacing: 9) {
                SafetyGaugeRing(gauge: model.gauge)
                Text(model.gauge.caption)
                    .font(VAFont.display(11, .medium))
                    .foregroundStyle(VA.secondary(0.55))
                    .multilineTextAlignment(.center)
                    .lineHeight(1.35, size: 11)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 178)
            .background(RoundedRectangle(cornerRadius: 22).fill(VA.card.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shelterWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAREST SHELTER")
                .font(VAFont.display(9.5))
                .tracking(em: 0.1, size: 9.5)
                .foregroundStyle(VA.secondary(0.45))
            Text("Metro\nVokzalna")
                .font(VAFont.display(17))
                .tracking(em: -0.01, size: 17)
                .foregroundStyle(.white)
            Text("240 m")
                .font(VAFont.rounded(24))
                .foregroundStyle(VA.green)
            Spacer(minLength: 0)
            Text("3 min walk · open")
                .font(VAFont.display(11, .medium))
                .foregroundStyle(VA.secondary(0.5))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 178)
        .background(RoundedRectangle(cornerRadius: 22).fill(VA.card.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    private var liveActivityBanner: some View {
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
                Text(model.etaShort)
                    .font(VAFont.rounded(20))
                    .foregroundStyle(VA.orange)
                    .contentTransition(.numericText())
            }
            Text("Kyiv Region — Area Status: Moderate Risk Zone.")
                .font(VAFont.display(14, .regular))
                .lineHeight(1.35, size: 14)
                .foregroundStyle(VA.secondary(0.85))
                .fixedSize(horizontal: false, vertical: true)
            ThreatProgressBar(progress: model.progress, track: 0.12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 24).fill(VA.card.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}
