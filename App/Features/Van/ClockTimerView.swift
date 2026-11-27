import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The gauge, grown to fill the screen: choose the length, the subject and block mode, then start
/// (syrup van design §6.2 to §6.4). It stands where the Focus tab's start screen stood.
struct ClockTimerView: View {
    @Environment(\.focusStores) private var focusStores
    @Environment(FocusTabState.self) private var tab
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets
    @Environment(SubjectStore.self) private var subjects
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(NotificationScheduler.self) private var reminders
    @AppStorage("van.blocksApps") private var wantsBlock = true
    /// The length last set, which the gauge shows too (`VanSceneView`); 0 until the clock has been turned.
    @AppStorage("van.minutes") private var savedMinutes = 0
    @State private var setting = ClockSetting(minutes: 50)
    @State private var notice: String?

    private var base: FocusPreset? { presets.presets.first { $0.id == presets.lastUsedID } ?? presets.presets.first }

    private func blocking(_ appSet: AppSet?) -> VanBlocking {
        VanBlocking(
            buildCanBlock: sessions.blocking.capability.canBlock, isAllowed: sessions.probe.isAllowed, wantsBlock: wantsBlock,
            hasApps: !(appSet?.summary.isEmpty ?? true)
        )
    }

    var body: some View {
        let preset = VanTimer.preset(from: base)
        let appSet = preset.appSetID.flatMap { appSets.set(id: $0) }
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VanBackButton(title: "Van") { router.selectedTab = .home }
                        Spacer(minLength: 0)
                    }
                    // The clock takes the whole width; minus and plus sit in the corners its circle leaves free.
                    ZStack(alignment: .bottom) {
                        ClockFace(setting: $setting)
                        HStack {
                            stepButton("minus", label: "Five minutes less") { setting.nudge(-1) }
                            Spacer(minLength: 0)
                            stepButton("plus", label: "Five minutes more") { setting.nudge(1) }
                        }
                    }
                    .frame(maxWidth: 420)
                    options(preset: preset, blocking: blocking(appSet))
                    if let notice {
                        Text(notice)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(VanPalette.outline)
                            .multilineTextAlignment(.center)
                    }
                    Button { start(preset: preset, appSet: appSet) } label: {
                        Text(VanTimer.startTitle(minutes: setting.minutes))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(VanPalette.outline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: 280)
                            .modifier(VanPlate(fill: VanPalette.goldLight))
                    }
                    .buttonStyle(.plain)
                    .disabled(sessions.isStarting)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { setting = ClockSetting(minutes: VanTimer.length(saved: savedMinutes, preset: base?.minutes)) }
        .onChange(of: setting.minutes) { _, minutes in savedMinutes = minutes }
    }

    private func options(preset: FocusPreset, blocking: VanBlocking) -> some View {
        VStack(spacing: 0) {
            Button { tab.selectedPresetID = preset.id; tab.sheet = .subject } label: {
                row("Subject", value: subjects.name(for: tab.subjectID(preset: preset.id, subjects: subjects)) ?? "None")
            }
            .buttonStyle(.plain)
            Divider().overlay(VanPalette.outline.opacity(0.25))
            Toggle(isOn: Binding(get: { blocking.canSwitch && wantsBlock }, set: { wantsBlock = $0 })) {
                Text("Block mode")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(VanPalette.outline)
            }
            .tint(VanPalette.syrup)
            .disabled(!blocking.canSwitch)
            .padding(.vertical, 12)
            Button {
                if blocking == .needsScreenTime {
                    // Apple's own prompt, asked once; after that iOS sends the member to Settings.
                    Task { _ = await sessions.requestAuthorization() }
                } else {
                    tab.selectedPresetID = preset.id
                    tab.sheet = .blocking
                }
            } label: {
                row(blocking.line, value: blocking.rowAction ?? "")
            }
            .buttonStyle(.plain)
            .disabled(blocking.rowAction == nil)
        }
        .padding(.horizontal, 16)
        .background(VanPalette.cream, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(VanPalette.outline, lineWidth: 2.5))
        .frame(maxWidth: 460)
    }

    private func row(_ title: String, value: String) -> some View {
        // One line when it fits; at large text sizes the value goes under its title.
        ViewThatFits(in: .horizontal) {
            HStack {
                rowTitle(title)
                Spacer(minLength: 8)
                rowValue(value)
            }
            VStack(alignment: .leading, spacing: 4) {
                rowTitle(title)
                rowValue(value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(VanPalette.outline)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func rowTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.body, design: .rounded).weight(.bold))
    }

    @ViewBuilder
    private func rowValue(_ value: String) -> some View {
        if !value.isEmpty {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .opacity(0.7)
                Image(systemName: "chevron.forward").font(.footnote.weight(.bold)).opacity(0.5)
            }
        }
    }

    private func stepButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // A fixed size: the button is a picture beside the clock, and the clock doesn't grow with the text.
            Image(systemName: image)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func start(preset: FocusPreset, appSet: AppSet?) {
        guard let focusStores, !sessions.isStarting else { return }
        let blocking = blocking(appSet)
        // Block mode with no apps chosen: choosing them comes first.
        if blocking == .chooseApps {
            tab.selectedPresetID = preset.id
            tab.sheet = .blocking
            return
        }
        let plain = blocking.startsPlainTimer
        let isFirstStart = !settings.hasStartedFocus
        let request = FocusSessionStore.StartRequest(
            preset: preset, minutes: setting.minutes, appSet: plain ? nil : appSet, plainTimer: plain, from: .focusTab,
            subject: tab.subjectID(preset: preset.id, subjects: subjects)
        )
        notice = nil
        Task {
            switch await focusStores.start(request, intention: nil, settings: settings) {
            case .started(let id):
                tab.lastStarted = id
                tab.subjectPick = nil
                // F1-23: asked once, at the first start, if iOS hasn't asked yet; never on a demo launch.
                if isFirstStart, reminders.schedulesReminders, reminders.authorization == .notDetermined {
                    await reminders.requestAuthorization()
                }
            case .alreadyRunning:
                break
            case .blockingFailed:
                notice = "Couldn't lock your apps. Turn block mode off to start a plain timer."
            case .ledgerUnavailable, .notRecorded:
                notice = FocusStartLines.couldntStart
            }
        }
    }
}
