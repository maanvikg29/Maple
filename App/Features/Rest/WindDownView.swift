import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Wind-down mode (spec §8.1): a dim bedside screen, presented full screen from Rest, Home's evening CTA or
/// anywhere else that offers "Start wind-down".
///
/// - The time in `heroNumeral` at 70%, and "38m until bed" under it.
/// - The primary "Goodnight" records the phone-down time in the bedside log (for Home's "Morning, no Apple Health"
///   numeral, spec §3.4); 10 seconds later the screen dims to black. A tap anywhere wakes it, and it dims again 10
///   seconds later. It never counts toward a leaf: the sleep leaves come only from Apple Health (spec D9).
/// - A close circle. There is no tree and there are no leaves, so there is nothing to browse at night.
/// - Ritual steps and a sounds capsule join it once those features ship.
struct WindDownView: View {
    /// How long the screen stays lit after Goodnight or a wake tap.
    static let dimDelay: Duration = .seconds(10)

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(ScheduleStore.self) private var schedule
    /// Read for the calendar only: nothing here records a night or earns a leaf.
    @Environment(CollectionStore.self) private var collection

    /// This session's Goodnight.
    @State private var goodnightAt: Date?
    @State private var isDark = false
    /// Bumped by every Goodnight and wake tap, which restarts the countdown to black.
    @State private var wakeCount = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = clock.date(forTimeline: context.date)
            ZStack {
                bedside(now: now)
                    .opacity(isDark ? 0 : 1)
                    .accessibilityHidden(isDark)
                if isDark {
                    darkness
                }
            }
        }
        .background(isDark ? Color.black : theme.colors.background)
        .mapleAnimation(isDark ? theme.motion.drift : theme.motion.gentle, value: isDark)
        .statusBarHidden()
        .persistentSystemOverlays(isDark ? .hidden : .automatic)
        .onAppear(perform: begin)
        .task(id: wakeCount) {
            guard goodnightAt != nil, !isDark else { return }
            try? await Task.sleep(for: Self.dimDelay)
            guard !Task.isCancelled else { return }
            isDark = true
        }
    }

    // MARK: Parts

    private func bedside(now: Date) -> some View {
        let calendar = collection.context.calendar
        let line = goodnightAt.map { goodnight in
            let text = RestCopy.phoneDown(at: HomeFormat.clockTime(of: goodnight, calendar: calendar), locale: locale)
            return (text: text, spoken: text + ".")
        } ?? RestCopy.bedsideLine(at: now, schedule: schedule.weekly, calendar: calendar, locale: locale)

        return VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.iconCircle)
                Spacer()
            }
            // The 44pt hit area overhangs the margin, so the circle lines up with it.
            .padding(.leading, -4)
            .padding(.top, theme.spacing.xs)

            Spacer(minLength: theme.spacing.xl)
            BedsideClock(time: HomeFormat.clockTime(of: now, calendar: calendar), line: line.text, spokenLine: line.spoken)
            Spacer(minLength: theme.spacing.xl)
            Spacer(minLength: 0)

            ZStack {
                Color.clear.frame(height: 52)
                if goodnightAt == nil {
                    Button("Goodnight", action: sayGoodnight)
                        .buttonStyle(.moonlight(dimmed: true))
                        .transition(.opacity)
                }
            }
            .padding(.bottom, theme.spacing.lg)
        }
        .padding(.horizontal, theme.spacing.homeMargin)
        .mapleAnimation(theme.motion.gentle, value: goodnightAt)
    }

    /// The dimmed screen: black, and one tap target that wakes it.
    private var darkness: some View {
        Color.black
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: wake)
            .accessibilityElement()
            .accessibilityLabel(Text("Screen dimmed"))
            .accessibilityHint(Text("Wakes the bedside clock"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, wake)
    }

    // MARK: Actions

    private func begin() {
        let now = clock.now()
        BedsideLog.shared.startWindDown(at: now, schedule: schedule.weekly, calendar: collection.context.calendar)
        #if DEBUG
        if RestDemo.saysGoodnight, goodnightAt == nil { sayGoodnight() }
        #endif
    }

    /// Goodnight: the phone-down time, kept in the bedside log for the wind-down state and the morning's "in bed"
    /// numeral when Apple Health has nothing (spec §3.4). It feeds no counter, so no leaf can be earned by tapping:
    /// nights come only from Apple Health (spec D9).
    private func sayGoodnight() {
        let now = clock.now()
        BedsideLog.shared.sayGoodnight(at: now)
        goodnightAt = now
        wakeCount += 1
    }

    private func wake() {
        isDark = false
        wakeCount += 1
    }
}
