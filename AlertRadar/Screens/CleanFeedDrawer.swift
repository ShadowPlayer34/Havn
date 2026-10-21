import SwiftUI

/// Option 1c — the feed you read when you want the facts. Verified reports only,
/// de-duplicated, each card carrying its own reliability. Tap a card to expand it.
struct CleanFeedDrawer: View {
    @Environment(ThreatModel.self) private var model
    @State private var dragOffset: CGFloat = 0

    /// 660 of the 874pt design canvas.
    private let heightFraction: CGFloat = 660.0 / 874.0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: geo.size.height * (1 - heightFraction))
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                // Grows as it is dragged down so no gap opens under the drawer.
                drawer
                    .frame(height: geo.size.height * heightFraction + dragOffset)
            }
            .offset(y: dragOffset)
        }
        .ignoresSafeArea()
    }

    private var drawer: some View {
        VStack(spacing: 14) {
            grabHandle
            header
            filters
            list
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Color(hex: 0x121214, opacity: 0.92))
                .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.7), radius: 30, y: -24)
        }
    }

    private var grabHandle: some View {
        Capsule()
            .fill(VA.secondary(0.28))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded {
                        if $0.translation.height > 120 { close() }
                        dragOffset = 0
                    }
            )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("Clean Feed")
                .font(VAFont.title)
                .tracking(em: -0.02, size: 24)
                .foregroundStyle(.white)
            Text(model.feedMeta)
                .font(VAFont.display(12, .medium))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }

    private var filters: some View {
        HStack(spacing: 7) {
            ForEach(FeedCategory.allCases) { category in
                let selected = model.filter == category
                Button {
                    model.filter = category
                } label: {
                    Text(category.rawValue)
                        .font(VAFont.display(12))
                        .foregroundStyle(selected ? .white : VA.secondary(0.5))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(selected ? VA.cyan.opacity(0.18) : .white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(selected ? VA.cyan.opacity(0.45) : .white.opacity(0.09), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.18), value: model.filter)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(model.visibleFeed) { item in
                    FeedCard(item: item, expanded: model.expandedItems.contains(item.id)) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                            model.toggleExpanded(item)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        Text("Hype and unverified reposts filtered: 41")
            .font(VAFont.display(14))
            .foregroundStyle(VA.secondary(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 15).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func close() {
        model.feedDrawerOpen = false
    }
}

struct FeedCard: View {
    let item: FeedItem
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(item.tag.rawValue)
                        .font(VAFont.mono(9.5, .semibold))
                        .tracking(em: 0.08, size: 9.5)
                        .foregroundStyle(item.tag.foreground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(item.tag.background))

                    Text(item.time)
                        .font(VAFont.mono(11.5))
                        .foregroundStyle(VA.secondary(0.5))

                    Spacer(minLength: 0)

                    HStack(spacing: 7) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule()
                                .fill(item.reliabilityColor)
                                .frame(width: 44 * CGFloat(item.reliability) / 100)
                        }
                        .frame(width: 44, height: 4)

                        Text("\(item.reliability)%")
                            .font(VAFont.rounded(11.5, .semibold))
                            .foregroundStyle(item.reliabilityColor)
                    }
                }

                Text(item.summary)
                    .font(VAFont.display(14.5, .regular))
                    .lineHeight(1.42, size: 14.5)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if expanded {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                        detailRow("COORD") {
                            Text(item.coords).font(VAFont.mono(11.5)).foregroundStyle(VA.cyan)
                        }
                        detailRow("SOURCE") {
                            Text(item.source).font(VAFont.display(11.5, .regular)).foregroundStyle(VA.secondary(0.8))
                        }
                        detailRow("MERGED") {
                            Text(item.merged).font(VAFont.display(11.5, .regular)).foregroundStyle(VA.secondary(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 11)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(hex: 0x545458, opacity: 0.45)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(VA.card))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func detailRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label)
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.06, size: 10)
                .foregroundStyle(VA.secondary(0.35))
            value()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
