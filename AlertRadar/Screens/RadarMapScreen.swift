import MapKit
import SwiftUI

/// Option 2a — the map you open. Liquid Glass chrome floating over real geography:
/// separate capsules up top, an edge layer tray, and one bottom cluster carrying the
/// countdown and the single action.
struct RadarMapScreen: View {
    @Environment(ThreatModel.self) private var model
    @Environment(LiveActivityController.self) private var liveActivity
    @Environment(ThreatViewModel.self) private var threats
    @Environment(ThreatZonesViewModel.self) private var zones
    @State private var location = LocationProvider()
    @State private var camera: MapCameraPosition = .region(ThreatScenario.region(around: LocationProvider.fallback))
    @State private var scale: MapScale?
    @State private var selectedShelter: Shelter?
    /// Pinned when the first fix lands: the incident stays where it is while you move.
    @State private var scenario = ThreatScenario(anchor: LocationProvider.fallback)
    /// The colour key is transient. Permanently parked over the city it is clutter on a
    /// screen whose whole job is the map underneath it, so it appears when it is asked
    /// for — once at launch, whenever the area layer is switched on, and from the menu —
    /// and takes itself away again.
    @State private var legendVisible = false
    @State private var legendTimer: Task<Void, Never>?
    @State private var legendShownThisLaunch = false

    var body: some View {
        @Bindable var model = model

        GeometryReader { geo in
            ZStack {
                map(height: geo.size.height)
                chrome

                if model.feedDrawerOpen {
                    CleanFeedDrawer()
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.feedDrawerOpen)
        .task { await location.start() }
        .onAppear { liveActivity.submit(activityState) }
        .onDisappear { legendTimer?.cancel() }
        .onChange(of: zones.hasLoaded) {
            // Once per launch, and keyed on the payload rather than on appearance: the
            // legend lists the classes actually on the map, so shown before the first
            // fetch lands it would be an empty card that times out before there is
            // anything to explain.
            guard zones.hasLoaded, !legendShownThisLaunch else { return }
            legendShownThisLaunch = true
            showLegend()
        }
        .onChange(of: model.showRiskArea) {
            // Switching the layer on is the moment its key is worth having; switching it
            // off makes the key meaningless, so it goes immediately rather than lingering.
            if model.showRiskArea {
                showLegend()
            } else {
                legendTimer?.cancel()
                withAnimation(.easeIn(duration: 0.25)) { legendVisible = false }
            }
        }
        // The overlay's own tick is the clock here: it moves every few seconds, and the
        // controller pushes only when the words actually change.
        .onChange(of: zones.tick) { liveActivity.submit(activityState) }
        .onChange(of: location.lastFix) {
            // Every accepted fix asks the backend; the view model debounces by 50 m / 30 s.
            guard let fix = location.lastFix else { return }
            threats.check(at: fix, force: false)
        }
        .onChange(of: threats.riskLevel) {
            scenario.risk = threats.response == nil ? .none : threats.riskLevel
            // A change of level should not wait for the next tick to reach the lock screen.
            liveActivity.submit(activityState)
        }
        .onChange(of: location.hasFix) {
            // Anchor the scenario and recentre once, on the first real fix.
            scenario = ThreatScenario(anchor: location.anchor, risk: threats.riskLevel)
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(ThreatScenario.region(around: location.anchor))
            }
        }
        .sheet(item: $selectedShelter) { shelter in
            ShelterDetailSheet(shelter: shelter)
                .presentationDetents([.height(ShelterDetailSheet.detentHeight), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.safetySheetOpen) {
            // `zone` is temporary — it only feeds the confidence card.
            SafetyProtocolSheet(zone: dominantZone)
                .presentationDetents([.height(SafetyProtocolSheet.detentHeight), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.dashboardOpen) {
            ThreatDashboardView()
                .presentationDetents([.fraction(ThreatDashboardView.detentFraction), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.systemSurfacesOpen) {
            SystemSurfacesScreen()
                .environment(model)
                .environment(liveActivity)
        }
    }

    // MARK: Map

    private func map(height: CGFloat) -> some View {
        Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
            if model.showRiskArea {
                if zones.hasLoaded {
                    // The backend's own polygons: risk as a wash, core dense on top.
                    ThreatZonesOverlay(zones: zones.zones)
                    if let zone = dominantZone, let anchor = zone.captionAnchor {
                        Annotation(coordinate: anchor) {
                            RiskAreaCaption(detail: zone.captionDetail, accent: zone.accent)
                        } label: {
                            EmptyView()
                        }
                    }
                } else if threats.riskLevel.isActionable {
                    // No geometry has ever arrived and the sector check still says there
                    // is something here. The wash is generated locally, and the caption
                    // says so rather than quoting district counts nobody sent us.
                    RiskHeatOverlay(scenario: scenario)
                    Annotation(coordinate: scenario.captionAnchor) {
                        RiskAreaCaption(detail: "LOCAL ESTIMATE · NO SERVER GEOMETRY")
                    } label: {
                        EmptyView()
                    }
                }
            }

            if model.showHavens {
                // Real register entries, nearest first. Only the closest few get a
                // label — a Kyiv street corner has a dozen within 300 m and the map
                // becomes unreadable.
                // Reversed so the nearest draws last and its label is not buried by the dots
                // behind it — Kyiv registers several entries at one address.
                ForEach(Array(threats.shelters.prefix(6).enumerated()).reversed(), id: \.element.id) { index, shelter in
                    // The labelled pin sits above its point; at this zoom two shelters
                    // 30 m apart are ~10 pt apart and a centred chip gets buried.
                    Annotation(coordinate: shelter.coordinate, anchor: index == 0 ? .bottom : .center) {
                        ShelterPin(shelter: shelter, isPrimary: index == 0) {
                            selectedShelter = shelter
                        }
                    } label: {
                        EmptyView()
                    }
                }
            }

            if location.hasFix {
                UserAnnotation { UserLocationDot() }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onMapCameraChange(frequency: .continuous) { context in
            scale = MapScale(region: context.region, mapHeight: height)
        }
        .ignoresSafeArea()
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topRow
            HStack { Spacer(); scaleIndicator }
                .padding(.top, 22)
                .padding(.trailing, 3)
            HStack(alignment: .top) {
                Spacer()
                VStack(spacing: 10) {
                    LayerTray()
                    recenterButton
                }
            }
            .padding(.top, 100)
            Spacer(minLength: 12)
            if legendVisible {
                HStack {
                    MapLegend(zones: zones.zones)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 4)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
            bottomCluster
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .opacity(model.feedDrawerOpen ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: model.feedDrawerOpen)
        .allowsHitTesting(!model.feedDrawerOpen)
        .overlay(alignment: .top) {
            // The location capsule stays legible above the feed drawer.
            if model.feedDrawerOpen {
                topRow
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
    }

    private var topRow: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                locationCapsule
                Spacer(minLength: 8)
                liveCapsule
                menuButton
            }
        }
    }

    private var locationCapsule: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusAccent)
                .frame(width: 9, height: 9)
                .shadow(color: statusAccent.opacity(0.9), radius: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(capsuleTitle)
                    .font(VAFont.display(13.5))
                    .tracking(em: -0.01, size: 13.5)
                    .foregroundStyle(.white)
                Text(capsuleSubtitle)
                    .font(VAFont.display(10.5, .medium))
                    .foregroundStyle(capsuleSubtitleColour)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 15)
        .padding(.vertical, 9)
        .vaGlass(RoundedRectangle(cornerRadius: 24))
    }

    /// Whether the feed can still be believed.
    ///
    /// Cyan, not green: green, orange and red are the risk scale everywhere else on this
    /// screen, and a green dot beside "8 Missile · in your district" reads as "all clear".
    /// Cyan is this design's interactive accent — it already carries "active, and not a
    /// statement about danger" on the recentre control — so it can say *live* without
    /// saying *safe*. Neutral grey was the first attempt at the same idea and failed the
    /// other way round: dimmed ink on a dimmed capsule reads as disconnected.
    ///
    /// It also has to be about *staleness*, not only about errors. `refresh()` swallows
    /// cancellation without recording one, so a poll loop that stops leaves `errorMessage`
    /// nil for ever and a pill testing only that would keep claiming "Live" over frozen
    /// geometry — the exact failure this pill exists to catch.
    private var liveCapsule: some View {
        // Its own clock. The overlay's `tick` is published by the same task that does the
        // polling, so if that task dies the tick dies with it and an age measured from it
        // would freeze at "fresh" precisely when the feed has stopped.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let status = feedStatus(at: context.date)
            HStack(spacing: 6) {
                if status.isLive {
                    Circle().fill(VA.cyan).frame(width: 6, height: 6).blink(2)
                } else {
                    // Hollow rather than filled: a feed that has stopped should not look
                    // like a feed with a quieter colour, it should look switched off.
                    Circle()
                        .strokeBorder(VA.secondary(0.55), lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                }
                Text(status.label)
                    .font(VAFont.display(11))
                    .foregroundStyle(status.isLive ? VA.cyanText : .white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .vaGlass(Capsule(), tint: status.isLive ? VA.cyan.opacity(0.3) : .white.opacity(0.16))
            .animation(.easeOut(duration: 0.25), value: status.label)
        }
    }

    /// Three missed polls at the zones view model's 30-second interval. Long enough that a
    /// slow network does not flicker the pill, short enough that a dead feed is named
    /// while the arrival window on screen is still worth acting on.
    private static let stalenessLimit: TimeInterval = 95

    /// What the pill says. Errors first — an unreachable backend is a stronger statement
    /// than an ageing payload, and it is the one the user can do something about.
    ///
    /// Both feeds count, and the older one wins: the overlay and the sector check run on
    /// separate clocks, and either going quiet is enough to make the screen wrong.
    private func feedStatus(at now: Date) -> (label: String, isLive: Bool) {
        if zones.errorMessage != nil || threats.errorMessage != nil {
            return ("Offline", false)
        }
        guard let updated = zones.lastUpdated else {
            return ("Connecting", false)
        }
        // The check only starts once a fix has landed, so a nil there is "not started
        // yet", not "stale" — the location capsule is already saying so in words.
        let age = now.timeIntervalSince(min(updated, threats.lastUpdated ?? updated))
        guard age > Self.stalenessLimit else { return ("Live", true) }
        // Minutes, floored: "Stale · 1 min" understates by less than a minute, and
        // rounding up would claim staleness the payload has not reached yet.
        return ("Stale · \(Int(age / 60)) min", false)
    }

    private var menuButton: some View {
        Menu {
            Button("Clean Feed", systemImage: "list.bullet.rectangle") {
                model.feedDrawerOpen = true
            }
            Button("Live Activity & Lock Screen", systemImage: "iphone.gen3") {
                model.systemSurfacesOpen = true
            }
            Button("Threat Check", systemImage: "shield.lefthalf.filled") {
                model.dashboardOpen = true
            }
            Button("Map Legend", systemImage: "paintpalette") {
                showLegend()
            }
        } label: {
            VStack(spacing: 3.5) {
                bar(16)
                bar(11)
                bar(16)
            }
            .frame(width: 44, height: 44)
            .vaGlass(Circle(), interactive: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    /// Back to where you are, at the scenario's own zoom.
    private var recenterButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) {
                camera = .region(ThreatScenario.region(around: location.anchor))
            }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VA.cyan)
                .frame(width: 52, height: 52)
                .vaGlass(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Centre on my location")
    }

    // MARK: Live status

    /// The zone standing over the user, when there is a real fix to test against.
    ///
    /// Gated on the server agreeing there is something here. The overlay's shapes are
    /// simplified for the wire — a few hundred metres of tolerance — so along a boundary
    /// they can disagree with `/threats/check`, which tests the exact geometry. One answer
    /// on screen, and it is the server's; this only decides *which* threat gets named.
    private var dominantZone: ThreatZone? {
        guard let coordinate = location.coordinate else { return nil }
        guard threats.response?.inRiskZone ?? true else { return nil }
        return zones.dominantZone(at: coordinate)
    }

    /// Recomputed off the store's tick, so the window decays between polls instead of
    /// standing still until the next snapshot version lands.
    private var arrival: ArrivalEstimate? {
        dominantZone?.arrival(at: zones.tick)
    }

    /// Computed here rather than read from `/threats/check`: that response is cached per
    /// snapshot version, so its `eta_window` would sit frozen for up to a batch window.
    /// The check's own wording is the fallback when there is no geometry to compute from.
    private var arrivalLabel: String? {
        arrival?.label ?? threats.response?.etaWindow
    }

    /// Report time … earliest arrival, so the bar shows the elapsed share of the flight
    /// and the countdown targets the conservative edge of the window.
    private var arrivalRange: ClosedRange<Date>? {
        if let zone = dominantZone, let earliest = zone.earliestArrival, earliest > .now {
            return zone.updatedAt...earliest
        }
        return threats.arrivalRange
    }

    /// No response yet is not "clear" — it stays neutral until the backend says otherwise.
    private var statusAccent: Color {
        threats.response == nil ? VA.secondary(0.5) : threats.riskLevel.accent
    }

    private var statusForeground: Color {
        threats.response == nil ? VA.secondary(0.75) : threats.riskLevel.badgeForeground
    }

    /// The place to name: the server's own gazetteer first, then the reverse-geocoded
    /// name. Nil without a fix — the provider falls back to a sample coordinate so the
    /// camera has somewhere to point, and that district is not where the user is.
    ///
    /// Shared with the Live Activity so the lock screen and the capsule cannot name two
    /// different places.
    private var areaName: String? {
        if let sector = threats.response?.sectorName { return sector }
        return location.hasFix ? location.displayName : nil
    }

    private var capsuleTitle: String { areaName ?? "Location unavailable" }

    /// What the lock screen would say right now, built from the same zone and the same
    /// check answer the cluster below is reading.
    private var activityState: ThreatActivityAttributes.ContentState {
        ThreatActivityAttributes.ContentState(
            area: areaName,
            zone: dominantZone,
            response: threats.response,
            now: zones.tick
        )
    }

    private var capsuleSubtitle: String {
        if let response = threats.response { return response.riskLevel.localizedShortStatus }
        // Checked before the error: with no coordinate no check is ever attempted, so
        // there is nothing for the network to have failed at.
        if !location.hasFix {
            return location.authorizationDenied ? "Location access is off" : "Waiting for location"
        }
        if threats.errorMessage != nil { return "No sector data" }
        return "Checking sector…"
    }

    private var capsuleSubtitleColour: Color {
        threats.response == nil ? VA.secondary(0.6) : threats.riskLevel.badgeForeground
    }

    /// What the cluster says when nothing is inbound.
    private var quietLine: String {
        guard let response = threats.response else {
            if !location.hasFix {
                // The overlay needs no coordinate, so say what is still true rather than
                // leaving the screen looking broken.
                return location.authorizationDenied
                    ? "Location is off, so your own sector cannot be checked. The map still shows every active zone."
                    : "Waiting for a location fix. The map still shows every active zone."
            }
            return threats.errorMessage ?? "Waiting for the first sector check."
        }
        if response.riskLevel != .none { return "No arrival estimate for this sector yet." }
        guard let nearest = threats.shelters.first else { return "Nothing inbound." }
        return "Nothing inbound. Nearest shelter is \(nearest.distanceLabel) away."
    }

    private var threatPillLabel: String {
        // The overlay knows how many of the thing were counted and which shape you are
        // standing in; the check only knows its type.
        if let zone = dominantZone {
            let subject = zone.count > 1
                ? "\(zone.count) \(zone.threatType.localizedName)"
                : zone.threatType.localizedName
            // *Which* threat comes from the overlay; *how close* comes from the server.
            // The overlay is thinned for the wire — kilometres of tolerance on an
            // oblast-sized shape — so `zone.kind` is not a fact about where the user is
            // standing, and stating it here is what put "in your district" on screen
            // under a capsule reading "Elevated attention".
            let placement = threats.riskLevel == .high ? "in your district" : "in the risk area"
            return "\(subject) · \(placement)"
        }
        guard let response = threats.response else {
            if !location.hasFix { return zonesSummary }
            return threats.errorMessage == nil ? "Awaiting sector check" : "Sector check unavailable"
        }
        if let threat = response.threatType {
            return "1 Active Threat · \(threat)"
        }
        return response.riskLevel == .none
            ? "No active threat in sector"
            : "\(response.riskLevel.localizedTitle) risk in sector"
    }

    /// The country-wide count, which `/threats/zones` answers without being told where
    /// anyone is. This is the one thing the screen can still state truthfully when there
    /// is no fix — and on a quiet night "no active threats" is the answer, not a failure.
    private var zonesSummary: String {
        guard zones.hasLoaded else {
            return zones.errorMessage == nil ? "Loading threat zones…" : "Threat zones unavailable"
        }
        return switch zones.activeThreatCount {
        case 0: "No active threats"
        case 1: "1 active threat on the map"
        case let count: "\(count) active threats on the map"
        }
    }

    /// Six seconds: long enough to read four short rows, short enough that it is gone
    /// before it becomes something to look past.
    private func showLegend() {
        legendTimer?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { legendVisible = true }
        legendTimer = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { legendVisible = false }
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white.opacity(0.9))
            .frame(width: width, height: 1.5)
    }

    private var scaleIndicator: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("\(scale?.zoomLabel ?? "DISTRICT") · \(scale?.ratioLabel ?? "1:10 000")")
                .font(VAFont.mono(8.5, .semibold))
                .tracking(em: 0.14, size: 8.5)
                .foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .bottom, spacing: 7) {
                Text(scale?.distanceLabel ?? "2 km")
                    .font(VAFont.mono(8.5, .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                ScaleBar(width: scale?.barWidth ?? 62)
            }
        }
        .animation(.easeOut(duration: 0.2), value: scale?.distanceLabel)
    }

    // MARK: Bottom cluster

    private var bottomCluster: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 13) {
                StatusPill(
                    dot: statusAccent,
                    blinkDuration: threats.riskLevel.isActionable ? 1.4 : nil,
                    tint: statusAccent.opacity(0.22),
                    stroke: statusAccent.opacity(0.45)
                ) {
                    Text(threatPillLabel)
                        .font(VAFont.display(12))
                        .tracking(em: -0.01, size: 12)
                        .foregroundStyle(statusForeground)
                }

                // The arrival block only exists when something is actually inbound; an empty
                // countdown frame reads as broken rather than calm.
                if let window = arrivalLabel {
                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ARRIVAL WINDOW")
                                .font(VAFont.display(10))
                                .tracking(em: 0.1, size: 10)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(window)
                                .font(VAFont.rounded(42))
                                .tracking(em: -0.035, size: 42)
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .animation(.snappy(duration: 0.3), value: window)
                        }
                        Spacer(minLength: 0)
                        if let range = arrivalRange {
                            VStack(alignment: .trailing, spacing: 5) {
                                // Ticks locally off the deadline rather than polling the backend.
                                Text(timerInterval: range, countsDown: true)
                                    .font(VAFont.mono(20, .semibold))
                                    .tracking(em: -0.02, size: 20)
                                    .foregroundStyle(VA.orange)
                                    .monospacedDigit()
                                Text("earliest arrival")
                                    .font(VAFont.display(10, .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    if let range = arrivalRange {
                        ThreatProgressTimer(range: range)
                    }
                } else {
                    Text(quietLine)
                        .font(VAFont.display(15, .regular))
                        .foregroundStyle(VA.secondary(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 15)
            .background(RoundedRectangle(cornerRadius: 30).fill(.black.opacity(0.3)))

            Button {
                model.safetySheetOpen = true
            } label: {
                Text("View Distance & Safety Protocol")
                    .font(VAFont.display(17.5))
                    .tracking(em: -0.015, size: 17.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(.glassProminent)
            .tint(threats.riskLevel.isActionable ? threats.riskLevel.accent : VA.cyan)
            .foregroundStyle(threats.riskLevel.isActionable ? .white : VA.cyanInk)
            .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .padding(8)
        .vaGlass(RoundedRectangle(cornerRadius: 38))
    }
}

struct ScaleBar: View {
    var width: CGFloat

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0.5, y: 0))
            path.addLine(to: CGPoint(x: 0.5, y: 4.5))
            path.addLine(to: CGPoint(x: width - 0.5, y: 4.5))
            path.addLine(to: CGPoint(x: width - 0.5, y: 0))
        }
        .stroke(.white.opacity(0.5), lineWidth: 1)
        .frame(width: width, height: 5)
    }
}

/// Two glass buttons on the right rail — the chip row moved to the edge so the
/// cluster below is free for the countdown and the one action.
struct LayerTray: View {
    @Environment(ThreatModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 6) {
                trayButton(label: "AREA", isOn: model.showRiskArea, hue: VA.orange) {
                    Circle()
                        .fill(RadialGradient(
                            stops: [
                                .init(color: VA.orange.opacity(0.95), location: 0),
                                .init(color: VA.orange.opacity(0), location: 0.72)
                            ],
                            center: .center, startRadius: 0, endRadius: 6.5
                        ))
                        .frame(width: 13, height: 13)
                } action: {
                    model.showRiskArea.toggle()
                }

                trayButton(label: "HAVENS", isOn: model.showHavens, hue: VA.green) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VA.green)
                        .frame(width: 11, height: 11)
                } action: {
                    model.showHavens.toggle()
                }
            }
        }
    }

    private func trayButton<Icon: View>(
        label: String,
        isOn: Bool,
        hue: Color,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: label == "AREA" ? 3 : 4) {
                icon()
                Text(label)
                    .font(VAFont.display(8))
                    .tracking(em: 0.02, size: 8)
                    .foregroundStyle(isOn ? .white : VA.secondary(0.45))
            }
            .frame(width: 52, height: 52)
            .vaGlass(Circle(), tint: isOn ? hue.opacity(0.35) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }
}
