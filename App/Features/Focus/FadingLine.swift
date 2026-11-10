import SwiftUI

/// A line under a session's dial whose words cross-fade by opacity alone when its `key` changes (F1 design §4.6): the
/// break's suggestion, and the running screen's leaf line as the leaf opens.
///
/// - **What fades:** only a change of `key`. Words that change under the same key (the leaf line's "· 17m to go" becoming
///   "· 16m to go") are drawn at once, so a calm screen doesn't pulse once a minute.
/// - **Layout:** the new words take the line's height at once, so nothing under the line moves during a fade, even
///   where the new words wrap to another number of lines (accessibility sizes). The words fading out sit in an overlay,
///   which takes no room.
/// - **The fade:** the new words fade in over the old ones fading out over `theme.motion.gentle`'s 0.6 s, stepped by
///   hand 30 times a second from a task, as the start screen's detail line steps its own, not by a SwiftUI animation or
///   transition. The new words are drawn from `value` itself, so whatever happens to the fade, the line says what the
///   screen decided.
///
/// ```swift
/// FadingLine(model.suggestion) { Text($0) }                                   // every new suggestion fades
/// FadingLine(words, key: model.leafOpened) { LeafLineRow(words: $0) }          // only the opening fades
/// ```
struct FadingLine<Value: Equatable & Sendable, Key: Equatable & Sendable, Content: View>: View {
    private let value: Value
    private let key: Key
    private let content: (Value) -> Content

    /// The key the last fade went to, and the words it is fading out.
    @State private var settledKey: Key
    @State private var leaving: Value?
    /// 0…1 through the fade.
    @State private var progress = 1.0
    @State private var fade: Task<Void, Never>?

    init(_ value: Value, key: Key, @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.key = key
        self.content = content
        _settledKey = State(initialValue: key)
    }

    var body: some View {
        // Until `onChange` has started the fade for a new key, the new words show as they are.
        let fading = key == settledKey && leaving != nil
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
            // One change handler for both, so the words a fade starts from are the ones drawn just before the key moved.
            .onChange(of: Shown(value: value, key: key)) { old, new in
                guard old.key != new.key else { return }
                crossFade(from: old.value, to: new.key)
            }
            .onDisappear {
                fade?.cancel()
                fade = nil
                leaving = nil
                settledKey = key
                progress = 1
            }
    }

    /// Fades from `old` to the words for `key`, by stepping `progress` (no SwiftUI animation).
    private func crossFade(from old: Value, to key: Key) {
        fade?.cancel()
        leaving = old
        settledKey = key
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

    /// The words on screen and the key they were drawn under.
    private struct Shown: Equatable {
        let value: Value
        let key: Key
    }
}

extension FadingLine where Key == Value {
    /// A line whose every change of words fades (the break's suggestion).
    init(_ value: Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.init(value, key: value, content: content)
    }
}

/// `FadingLine`'s length: `theme.motion.gentle`'s 0.6 s. (A generic type can't hold a static stored property.)
private enum FadingLineTiming {
    static let seconds = 0.6
}
