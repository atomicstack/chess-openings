import Foundation
import SwiftData

/// Snapshot of an in-progress session — either a mid-drill or a
/// mid-playout — so the app can resume from where the user left off
/// after a restart or a fresh install/upgrade. Written every time the
/// session's history changes and cleared when the user exits or the
/// game ends.
///
/// The snapshot is intentionally minimal — what's needed to navigate
/// the user back to the right line and replay the moves into a fresh
/// session. One row per `(openingId, lineId)` pair, and the row's
/// `phase` distinguishes which kind of session it represents.
///
/// Name kept as `PersistedPlayoutState` because renaming a `@Model`
/// breaks SwiftData migration; semantically it now persists either
/// session type.
@Model
final class PersistedPlayoutState {
    var openingId: UUID
    var lineId: UUID
    /// FEN of the position the session started from. For a playout
    /// snapshot this is the drill's final position. For a drill
    /// snapshot it's the standard starting position.
    var startingFEN: String
    /// `"white"` or `"black"` — the user's side. Stored as raw so
    /// SwiftData doesn't need a custom enum codec.
    var userSideRaw: String
    /// 0…20 skill at which the engine plays its replies. Unused but
    /// preserved for drill snapshots.
    var engineLevel: Int
    /// JSON-encoded `[StoredMove]`. For playout snapshots this is the
    /// playout history; for drill snapshots it's the drill history.
    /// Same approach the project already uses for `Line.pliesData`.
    var movesData: Data
    /// `"drill"` or `"playout"`. Optional for migration safety —
    /// rows written by earlier app versions don't have this column
    /// and are treated as playout snapshots (which is what they were).
    var phase: String?
    var savedAt: Date

    init(
        openingId: UUID,
        lineId: UUID,
        startingFEN: String,
        userSideRaw: String,
        engineLevel: Int,
        movesData: Data,
        phase: Phase = .playout,
        savedAt: Date = .init()
    ) {
        self.openingId = openingId
        self.lineId = lineId
        self.startingFEN = startingFEN
        self.userSideRaw = userSideRaw
        self.engineLevel = engineLevel
        self.movesData = movesData
        self.phase = phase.rawValue
        self.savedAt = savedAt
    }

    /// Decoded moves. Returns `[]` on malformed payloads (defensive
    /// against corrupted on-disk state).
    var moves: [StoredMove] {
        get { (try? JSONDecoder().decode([StoredMove].self, from: movesData)) ?? [] }
        set { movesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Typed view of `phase`. Defaults to `.playout` for legacy rows
    /// (where the column is nil) so the existing resume path keeps
    /// working without a migration step.
    var phaseKind: Phase {
        Phase(rawValue: phase ?? Phase.playout.rawValue) ?? .playout
    }

    enum Phase: String {
        case drill
        case playout
    }
}
