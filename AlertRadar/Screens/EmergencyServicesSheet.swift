import CoreLocation
import SwiftUI

/// One number on the emergency screen. `number` is as printed ("15-80"); the dialled form
/// drops everything but the digits.
struct EmergencyLine: Identifiable, Equatable {
    let number: String
    let name: String
    let detail: String
    /// The service's dot on the grid. Nil for city lines, which carry no accent.
    var color: Color?

    var id: String { number }

    var telURL: URL? { URL(string: "tel:\(number.filter(\.isNumber))") }

    static let single = EmergencyLine(
        number: "112", name: "Single emergency line", detail: "Connects to any service", color: VA.red
    )

    static let services: [EmergencyLine] = [
        EmergencyLine(number: "101", name: "Rescue · DSNS", detail: "Fire, rubble, rescue", color: VA.orange),
        EmergencyLine(number: "102", name: "Police", detail: "Crime, suspicious objects", color: VA.cyan),
        EmergencyLine(number: "103", name: "Ambulance", detail: "Injuries, medical help", color: VA.red),
        EmergencyLine(number: "104", name: "Gas service", detail: "Gas leaks", color: Color(hex: 0xFFD60A)),
    ]

    static let cityLines: [EmergencyLine] = [
        EmergencyLine(number: "1551", name: "Kyiv city contact centre", detail: "Utilities, heating, shelter access"),
        EmergencyLine(number: "15-80", name: "Kyiv emergency hotline", detail: "Damaged buildings after strikes"),
    ]
}

/// Emergency services and quick dial — design option 3c. Every number goes through a
/// confirm card first: a mis-tap on a grid this dense should not ring the police.
///
/// The design's "My contacts" and "I'm safe" rows are not here yet — they need a contacts
/// picker and SMS, which the app does not have.
struct EmergencyServicesSheet: View {
    /// Shown on the confirm card so it can be read out to the operator.
    var coordinate: CLLocationCoordinate2D?

    @Environment(\.openURL) private var openURL
    @State private var pending: EmergencyLine?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    singleLineCard
                    servicesGrid
                    sectionLabel("KYIV · CITY LINES")
                    cityList
                }
                .padding(.horizontal, 16)
                // Clear of the system grabber.
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            if let pending {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { self.pending = nil }
                    .transition(.opacity)
                confirmCard(pending)
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: pending)
        .background(VA.canvas)
    }

    // MARK: Directory

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Emergency")
                .font(VAFont.display(34, .bold))
                .tracking(em: -0.02, size: 34)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text("Free · no SIM needed for 112")
                .font(VAFont.display(12, .medium))
                .foregroundStyle(VA.secondary(0.45))
        }
        .padding(.horizontal, 4)
    }

    private var singleLineCard: some View {
        let line = EmergencyLine.single
        return Button {
            pending = line
        } label: {
            HStack(spacing: 16) {
                Text(line.number)
                    .font(VAFont.rounded(46))
                    .tracking(em: -0.02, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.name)
                        .font(VAFont.display(17))
                    Text(line.detail)
                        .font(VAFont.display(12.5, .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xFF5A52, opacity: 0.9), Color(hex: 0xFF2D22, opacity: 0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: VA.red.opacity(0.25), radius: 15, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call 112, \(line.name)")
    }

    private var servicesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(EmergencyLine.services) { line in
                Button {
                    pending = line
                } label: {
                    serviceTile(line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(line.number), \(line.name)")
            }
        }
    }

    private func serviceTile(_ line: EmergencyLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(line.color ?? VA.secondary())
                    .frame(width: 8, height: 8)
                Text(line.name)
                    .font(VAFont.display(12))
                    .foregroundStyle(VA.secondary(0.7))
                    .lineLimit(1)
            }
            Text(line.number)
                .font(VAFont.rounded(36))
                .tracking(em: -0.02, size: 36)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(line.detail)
                .font(VAFont.display(11.5, .regular))
                .foregroundStyle(VA.secondary(0.5))
                .lineLimit(2)
        }
        .padding(14)
        // The design's 118 includes the padding (`box-sizing: border-box`).
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(VAFont.display(10))
            .tracking(em: 0.1, size: 10)
            .foregroundStyle(VA.secondary(0.45))
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    private var cityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(EmergencyLine.cityLines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                }
                Button {
                    pending = line
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name)
                                .font(VAFont.display(15, .medium))
                                .foregroundStyle(.white)
                            Text(line.detail)
                                .font(VAFont.display(12, .regular))
                                .foregroundStyle(VA.secondary(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(line.number)
                            .font(VAFont.mono(16, .semibold))
                            .foregroundStyle(Color(hex: 0x5CC2F0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(line.number), \(line.name)")
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Confirm

    private func confirmCard(_ line: EmergencyLine) -> some View {
        VStack(spacing: 6) {
            Text(line.number)
                .font(VAFont.rounded(52))
                .tracking(em: -0.02, size: 52)
                .foregroundStyle(.white)
            Text(line.name)
                .font(VAFont.display(15, .medium))
                .foregroundStyle(VA.secondary(0.7))

            // The design promises the address on screen *during* the call; once the dialler
            // takes over this app is not on screen, so the coordinates go here instead.
            locationNote
                .padding(.top, 6)

            VStack(spacing: 8) {
                Button {
                    pending = nil
                    if let url = line.telURL { openURL(url) }
                } label: {
                    Text("Call \(line.number)")
                        .font(VAFont.display(17))
                        .foregroundStyle(Color(hex: 0x00210B))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Color(hex: 0x48D66E, opacity: 0.95), Color(hex: 0x28B450, opacity: 0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button {
                    pending = nil
                } label: {
                    Text("Cancel")
                        .font(VAFont.display(16))
                        .foregroundStyle(Color(hex: 0x5CC2F0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 34).fill(.black.opacity(0.32)))
        .padding(8)
        .vaGlass(RoundedRectangle(cornerRadius: 42))
    }

    @ViewBuilder private var locationNote: some View {
        if let coordinate {
            VStack(spacing: 4) {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(VAFont.mono(15, .semibold))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                Text("Your coordinates — read them out if you cannot name the address.")
                    .font(VAFont.display(12.5, .regular))
                    .foregroundStyle(VA.secondary(0.5))
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("No location fix — name the nearest street or landmark.")
                .font(VAFont.display(12.5, .regular))
                .foregroundStyle(VA.secondary(0.5))
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    EmergencyServicesSheet(coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234))
        .preferredColorScheme(.dark)
}
