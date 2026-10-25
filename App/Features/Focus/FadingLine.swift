import SwiftUI

/// A line under a session's dial whose words cross-fade by opacity alone (F1 design §4.6): the break's suggestion and
/// the running screen's leaf line.
///
/// - **Layout:** the new words take the line's height at once, so nothing under the line moves during the fade, even
///   where the new words wrap to another number of lines (accessibility sizes). The words fading out sit in an overlay,
///   which takes no room.
/// - **The fade:** the new words fade in over the old ones fading out over `theme.motion.gentle`'s 0.6 s, stepped by
///   hand 30 times a second from a task, as the start screen's detail line steps its own, not by a SwiftUI animation or
///   transition. The new words are drawn from `value` itself, so whatever happens to the fade, the line says what the
///   screen decided.
///
/// ```swift
/// FadingLine(model.suggestion) { Text($0) }
/// ```
struct FadingLine<Value: Equatable & Sendable, Content: View>: View {
    private let value: Value
    private let content: (Value) -> Content

    /// The value the last fade went to, and the one it is fading out.
    @State private var settled: Value
    @State private var leaving: Value?
    /// 0…1 through the fade.
    @State private var progress = 1.0
    @State private var fade: Task<Void, Never>?

    init(_ value: Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.content = content
        _settled = State(initialValue: value)
    }

    var body: some View {
        // Until `onChange` has started the fade to new words, they show as they are.
        let fading = value == settled
        let eased = progress * progress * (3 - 2 * progress)
        content(value)
            .frame(maxWidth: .infinity)
            .opacity(fading ? eased : 1)
            .overlay(alignment: .top) {
                if fading, let leaving {
                    content(leaving)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(1 - eased)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: value) { _, new in crossFade(to: new) }
            .onDisappear {
                fade?.cancel()
                fade = nil
                leaving = nil
                settled = value
                progress = 1
            }
    }

    /// Fades from what is on screen to `new`, by stepping `progress` (no SwiftUI animation).
    private func crossFade(to new: Value) {
        fade?.cancel()
        leaving = settled == new ? nil : settled
        settled = new
        progress = 0
        fade = Task {
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / 30))
                guard !Task.isCancelled else { return }
                let step = min(1, Date().timeIntervalSince(start) / FadingLineTiming.seconds)
                progress = step
                if step >= 1 {
                    leaving = nil
                    fade = nil
                    return
                }
            }
        }
    }
}

/// `FadingLine`'s length: `theme.motion.gentle`'s 0.6 s. (A generic type can't hold a static stored property.)
private enum FadingLineTiming {
    static let seconds = 0.6
}
