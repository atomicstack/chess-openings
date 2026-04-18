import Foundation
import AVFoundation

/// Plays short sound effects. The protocol keeps call sites decoupled
/// from `AVAudioPlayer` so views can be tested against a fake.
protocol AudioServicing: AnyObject {
    func play(_ effect: SoundEffect)
}

/// Default `AudioServicing` implementation backed by `AVAudioPlayer`.
///
/// One player per effect is lazily created and cached so repeat plays
/// don't re-decode the mp3. The shared session is set to `.ambient`
/// so the app mixes politely with music and background audio.
///
/// `isEnabled` is injected as a closure so callers can wire it to any
/// reactive storage (e.g. a SwiftData `UserSettings.soundsEnabled`).
///
/// The class is `@MainActor` to match the default actor isolation used
/// by the rest of the app — it's called from SwiftUI views.
@MainActor
final class AudioService: AudioServicing {
    private let isEnabled: () -> Bool
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var sessionConfigured = false

    /// Last effect the service attempted to play while un-muted.
    /// Exposed primarily for tests.
    private(set) var lastAttemptedEffect: SoundEffect? = nil

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        // Session config is deferred to first real play() call. Touching
        // `AVAudioSession` inside the xctest host on the simulator has
        // been observed to abort the process at teardown, so we only
        // configure the session when we're actually about to make noise.
    }

    /// Keep deinit nonisolated so the runtime doesn't hop to MainActor
    /// for teardown. There's a long-standing simulator bug that aborts
    /// the test host when a `@MainActor` class is dealloc'd via the
    /// actor-isolated deinit path.
    nonisolated deinit { }

    func play(_ effect: SoundEffect) {
        lastAttemptedEffect = effect
        guard isEnabled() else {
            lastAttemptedEffect = nil
            return
        }
        guard let player = loadPlayer(for: effect) else { return }
        configureSessionIfNeeded()
        player.currentTime = 0
        player.play()
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func loadPlayer(for effect: SoundEffect) -> AVAudioPlayer? {
        if let existing = players[effect] { return existing }
        guard let url = Bundle.main.url(forResource: effect.fileName, withExtension: "mp3") else {
            assertionFailure("missing sound: \(effect.fileName).mp3")
            return nil
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[effect] = player
        return player
    }
}
