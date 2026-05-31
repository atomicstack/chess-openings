import Foundation
import SwiftData

/// Singleton-by-convention snapshot of an in-progress engine playout
/// so the app can resume from where the user left off after a restart
/// or a fresh install/upgrade. Written every time the playout's
/// history changes and cleared when the user exits or the game ends.
///
/// The snapshot is intentionally minimal — what's needed to navigate
/// the user back to the right line and replay the moves into a fresh
/// `EnginePlayoutSession`.
@Model
final class PersistedPlayoutState {
    var openingId: UUID
    var lineId: UUID
    /// FEN of the position the playout started from (i.e. the drill's
    /// final position when the user tapped "play it out →").
    var startingFEN: String
    /// `"white"` or `"black"` — the user's side. Stored as raw so
    /// SwiftData doesn't need a custom enum codec.
    var userSideRaw: String
    /// 0…20 skill at which the engine plays its replies.
    var engineLevel: Int
    /// JSON-encoded `[StoredMove]`. Same approach the project already
    /// uses for `Line.pliesData`.
    var movesData: Data
    var savedAt: Date

    init(
        openingId: UUID,
        lineId: UUID,
        startingFEN: String,
        userSideRaw: String,
        engineLevel: Int,
        movesData: Data,
        savedAt: Date = .init()
    ) {
        self.openingId = openingId
        self.lineId = lineId
        self.startingFEN = startingFEN
        self.userSideRaw = userSideRaw
        self.engineLevel = engineLevel
        self.movesData = movesData
        self.savedAt = savedAt
    }

    /// Decoded moves. Returns `[]` on malformed payloads (defensive
    /// against corrupted on-disk state).
    var moves: [StoredMove] {
        get { (try? JSONDecoder().decode([StoredMove].self, from: movesData)) ?? [] }
        set { movesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
