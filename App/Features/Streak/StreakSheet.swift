import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The bedtime run (spec §8.6), a `.medium` sheet from Home's streak: the amber moon and run numeral, the best
/// run, the last 14 nights, how a run is kept, and the next Bedtime-runs leaf.
struct StreakSheet: View {
    @Environment(CollectionStore.self) private var collection
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var moonSize: CGFloat = 40
    @Namespace private var zoom
    @State private var pushedLeaf: String?
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            content(now: clock.now())
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(item: $pushedLeaf) { speciesID in
                    LeafDetailView(speciesID: speciesID)
                        .navigationTransition(.zoom(sourceID: speciesID, in: zoom))
                }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(theme.colors.surface2)
        .onChange(of: pushedLeaf) { _, leaf in
            // Leaf detail needs the room.
            if leaf != nil { detent = .large }
        }
    }

    private func content(now: Date) -> some View {
        let run = collection.currentBedtimeRun
        let best = Int(collection.snapshot.counters[.bedtimeRun] ?? 0)
        let calendar = collection.context.calendar
        let lastNight = LocalDay(now, calendar: calendar).adding(days: -1, calendar: calendar)
        let marks = BedtimeRunNights.marks(
            nights: collection.snapshot.recentNights, currentRun: run, lastNight: lastNight, calendar: calendar
        )
        let next = collection.progress(at: now)
            .filter { $0.category == .bedtimeRun && $0.state == .locked && $0.availability == .available }
            .min { $0.threshold < $1.threshold }
        let phase = collection.phase(at: now)

        return ScrollView {
            VStack(spacing: 0) {
                hero(run: run)
                    .padding(.top, theme.spacing.xl)

                VStack(spacing: theme.spacing.xxs) {
                    Text("night run")
                        .font(MapleFont.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                    if best > 0 {
                        Text("Best run: \(best) \(best == 1 ? "night" : "nights")")
                            .font(MapleFont.footnote.monospacedDigit())
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, theme.spacing.xxs)

                BedtimeRunRow(marks: marks)
                    .padding(.top, theme.spacing.xl)

                Text(RewardCategoryInfo(.bedtimeRun).definition)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacing.sm)

                if let next {
                    NextLeafRow(.leaf(next, remainder: LeafRemainder(next, phase: phase))) {
                        pushedLeaf = next.speciesID
                    }
                    .zoomSource(id: next.speciesID, in: zoom)
                    .padding(.top, theme.spacing.lg)
                }
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.bottom, theme.spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The amber moon and the run numeral, both `reward` (one of the few places amber belongs, spec §1.3).
    private func hero(run: Int) -> some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Image(systemName: "moon.fill")
                .font(.system(size: min(moonSize, 56), weight: .regular))
            Text(run, format: .number)
                .font(MapleFont.numeral(size: min(numeralSize, 88)))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: Double(run)))
        }
        .foregroundStyle(theme.colors.reward)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeSpeech.streak(nights: run))
        .accessibilityAddTraits(.isHeader)
    }
}
