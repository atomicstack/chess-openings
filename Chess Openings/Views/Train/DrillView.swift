import SwiftUI
import SwiftData
import ChessKit

struct DrillView: View {
    let opening: Opening
    let line: Line

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]
    @Query private var persistedPlayouts: [PersistedPlayoutState]
    @State private var session: DrillSession?
    @State private var playoutStartingFEN: String?
    @State private var hintShown: Bool = false
    @State private var solutionShown: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var audio: AudioService?
    @State private var playout: EnginePlayoutSession?
    @State private var engineService: EngineService?
    @State private var playoutHint: EngineMove?
    @State private var wasLearnedAtSessionStart: Bool = false
    @State private var confettiTrigger: Date?
    @State private var moveAnnotation: MoveAnnotation?
    @State private var pendingConfirmation: PlayoutConfirmation?
    /// Bestmove search fired while the user is on the clock. Returns
    /// the position it was started for plus the resulting decision so
    /// the post-move analyser can verify it's still relevant before
    /// using the cached result.
    @State private var precomputeTask: Task<(position: Position, decision: EngineDecision?), Never>?

    /// Which match-management action is awaiting user confirmation.
    /// `nil` when no modal is up.
    enum PlayoutConfirmation: Identifiable {
        case draw, resign, exit

        var id: Self { self }

        var title: String {
            switch self {
            case .draw:   return "offer a draw?"
            case .resign: return "resign the game?"
            case .exit:   return "exit playout?"
            }
        }

        var message: String {
            switch self {
            case .draw:   return "stockfish will accept if the position is roughly equal, otherwise the game continues."
            case .resign: return "stockfish takes the win immediately and this game ends."
            case .exit:   return "your current game will end."
            }
        }

        var confirmLabel: String {
            switch self {
            case .draw:   return "offer"
            case .resign: return "resign"
            case .exit:   return "exit"
            }
        }

        var confirmRole: ButtonRole? {
            switch self {
            case .draw:   return nil
            case .resign: return .destructive
            case .exit:   return .destructive
            }
        }
    }

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        VStack(spacing: 12) {
            if let s = session {
                BoardView(
                    position: playout?.position ?? s.position,
                    orientation: opening.side,
                    highlights: boardHighlights(for: s),
                    bestMoveArrow: bestMoveArrow(for: s),
                    moveAnnotation: playout != nil ? moveAnnotation : nil,
                    moveAnnotationDurationMs: settings?.moveQualityBadgeMs ?? 1500,
                    onMove: { move in
                        if let p = playout {
                            Task { await p.submit(move) }
                        } else {
                            Task { await s.submit(move) }
                        }
                    }
                )
                .padding(.horizontal)

                if let p = playout {
                    PlayoutPromptRow(
                        session: p,
                        onAcceptEngineResign: { p.acceptEngineResignation() },
                        onDeclineEngineResign: { p.declineEngineResignation() }
                    )
                    moveListRow(forPlayout: p, drill: s)
                    Spacer()
                    PlayoutControlsRow(
                        session: p,
                        hintShown: $hintShown,
                        solutionShown: $solutionShown,
                        onResign: { withAnimation(.easeOut(duration: 0.18)) { pendingConfirmation = .resign } },
                        onOfferDraw: { withAnimation(.easeOut(duration: 0.18)) { pendingConfirmation = .draw } },
                        onExitPlayout: { withAnimation(.easeOut(duration: 0.18)) { pendingConfirmation = .exit } }
                    )
                    Spacer()
                } else {
                    promptRow(for: s)
                    moveListRow(for: s)
                    Spacer()
                    controlsRow(for: s)
                    Spacer()
                }
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            BrainThinkingIndicator(
                isThinking: playout?.status == .engineThinking
            )
        }
        .overlay {
            ConfettiBurst(trigger: confettiTrigger)
                .allowsHitTesting(false)
        }
        .overlay {
            if let confirmation = pendingConfirmation {
                ConfirmationModal(
                    title: confirmation.title,
                    message: confirmation.message,
                    confirmLabel: confirmation.confirmLabel,
                    confirmRole: confirmation.confirmRole,
                    onConfirm: {
                        executePendingConfirmation(confirmation)
                        withAnimation(.easeIn(duration: 0.14)) {
                            pendingConfirmation = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeIn(duration: 0.14)) {
                            pendingConfirmation = nil
                        }
                    }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(opening.name)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Text(line.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettingsSheet = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("settings")
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
        .onAppear { startSessionIfNeeded() }
        .onChange(of: session?.history.count ?? 0) { _, _ in
            // Any applied move — user, reply, autoplay, undo, reset —
            // invalidates whatever hint/solution the user had visible.
            // Force them to explicitly re-enable for the next move.
            hintShown = false
            solutionShown = false
            // Persist the current drill snapshot so a relaunch can
            // resume mid-drill. snapshotDrillState skips itself if a
            // playout is active (the playout watcher owns that case).
            snapshotDrillState()
        }
        .onChange(of: hintShown) { _, _ in
            refreshPlayoutHintIfNeeded()
        }
        .onChange(of: solutionShown) { _, _ in
            refreshPlayoutHintIfNeeded()
        }
        .onChange(of: playout?.history.count ?? 0) { _, _ in
            // Mirror drill behaviour: a new move invalidates whatever
            // hint/solution was visible. User must re-enable to see
            // the hint for the next position.
            hintShown = false
            solutionShown = false
            refreshPlayoutHintIfNeeded()
            // Persist the current playout snapshot so a relaunch can
            // resume from this ply.
            snapshotPlayoutState()
        }
        .onChange(of: playoutGameIsOver) { _, isOver in
            // The game ended (mate, resign, draw, etc.). Wipe the
            // snapshot so the next launch doesn't try to resume into
            // a finished game.
            if isOver { clearPersistedPlayout() }
        }
        .onChange(of: userOnPlayoutClock, initial: true) { _, onClock in
            // Run the bestmove search for the user's current position
            // while they think, so the post-move analyser can re-use
            // it instead of running it then.
            if onClock {
                schedulePlayoutPrecompute()
            }
        }
    }

    // MARK: - subviews

    @ViewBuilder
    private func promptRow(for s: DrillSession) -> some View {
        HStack {
            if case .lineComplete = s.status {
                completeBanner(for: s)
            } else {
                Text(promptText(for: s))
                    .font(.callout)
                    .foregroundStyle(promptColor(for: s))
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    /// End-of-line banner. Text is "perfect" for a clean run, otherwise
    /// "line complete". A bouncing green checkmark always trails; if the
    /// run also averaged under 1 second per ply, a "speedy" tag with a
    /// bouncing yellow bolt is appended.
    @ViewBuilder
    private func completeBanner(for s: DrillSession) -> some View {
        HStack(spacing: 6) {
            Text(s.completedWithoutMistake ? "perfect" : "line complete")
                .font(.callout)
                .foregroundStyle(.green)
            Image(systemName: "checkmark")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .repeat(.continuous))
            if isSpeedy(s) {
                Text("speedy")
                    .font(.callout)
                    .foregroundStyle(.yellow)
                Image(systemName: "bolt.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.yellow)
                    .symbolEffect(.bounce, options: .repeat(.continuous))
            }
            Button("play it out →") {
                startPlayout(from: s)
            }
            .font(.callout)
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.leading, 8)
        }
    }

    /// True when the user averaged under a second per ply on this run.
    /// Returns false if the session never started the clock (e.g. an
    /// all-autoplay line), so the speedy tag only rewards actual play.
    private func isSpeedy(_ s: DrillSession) -> Bool {
        guard let avg = s.averageSecondsPerPly else { return false }
        return avg < 1.0
    }

    private func moveListRow(for s: DrillSession) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                    ForEach(Array(s.history.enumerated()), id: \.offset) { i, move in
                        let pre = i < s.preMovePositions.count ? s.preMovePositions[i] : Position.standard
                        let san = SanCodec.format(move, in: pre)
                        Text(sanLabel(ply: i, san: san))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(progressLabel(for: s))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: 160, alignment: .top)
        .padding(.horizontal)
    }

    /// Renders the drill's opening trail (in secondary) followed by
    /// the playout's continuation (in primary), as one continuous
    /// move list. Right-hand label is "move N" where N is the
    /// full-move count.
    private func moveListRow(
        forPlayout p: EnginePlayoutSession,
        drill s: DrillSession
    ) -> some View {
        let drillCount = s.history.count
        let combinedMoves = s.history + p.history
        let combinedPres = s.preMovePositions + p.preMovePositions
        return HStack(alignment: .top, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                    ForEach(Array(combinedMoves.enumerated()), id: \.offset) { i, move in
                        let pre = i < combinedPres.count ? combinedPres[i] : Position.standard
                        let san = SanCodec.format(move, in: pre)
                        Text(sanLabel(ply: i, san: san))
                            .font(.caption.monospaced())
                            .foregroundStyle(i < drillCount ? .secondary : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("move \(combinedMoves.count / 2 + 1)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: 160, alignment: .top)
        .padding(.horizontal)
    }

    private func progressLabel(for s: DrillSession) -> String {
        let p = DrillProgress.userMoves(
            historyCount: s.history.count,
            totalPlies: line.plies.count,
            side: opening.side
        )
        return "\(p.played)/\(p.total)"
    }

    private func controlsRow(for s: DrillSession) -> some View {
        HStack(spacing: 0) {
            Button {
                hintShown.toggle()
                if hintShown { solutionShown = false }
            } label: {
                Label(hintShown ? "hide hint" : "hint", systemImage: "lightbulb")
            }
            .tint(.green)
            .disabled(s.status == .lineComplete)
            .frame(maxWidth: .infinity)

            Button {
                solutionShown.toggle()
                if solutionShown { hintShown = false }
            } label: {
                Label(solutionShown ? "hide" : "solution", systemImage: "eye")
            }
            .tint(.blue)
            .disabled(s.status == .lineComplete)
            .frame(maxWidth: .infinity)

            Button {
                s.undo()
            } label: {
                Label("undo", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
            .disabled(s.history.isEmpty)
            .frame(maxWidth: .infinity)

            Button {
                s.reset()
                if opening.side == .black {
                    scheduleBlackSideAutoplay(on: s)
                }
            } label: {
                Label("reset", systemImage: "arrow.clockwise")
            }
            .tint(.red)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    // MARK: - state helpers

    private func startSessionIfNeeded() {
        guard session == nil else { return }
        let snapshot = LineSnapshot(plies: line.plies)
        let oracle = LineBookOracle(plies: line.plies)
        let mode = settings?.drillMode ?? .strict
        let threshold = settings?.masteryThreshold ?? 3
        let initialStreak = line.mastery?.correctStreak ?? 0
        // Snapshot the learned state at session start so onLineComplete
        // can tell when the run *just* tipped the line into learned.
        wasLearnedAtSessionStart = line.mastery?.isLearned ?? false
        let s = DrillSession(
            line: snapshot,
            oracle: oracle,
            mode: mode,
            masteryThreshold: threshold,
            initialStreak: initialStreak
        )
        s.scriptedReplyDelayMs = 750
        let player = AudioService(isEnabled: { [settingsList] in
            settingsList.first?.soundsEnabled ?? true
        })
        s.onMoveApplied = { move, pre, post, byUser in
            let sfx = SoundEffect.forMove(move, pre: pre, post: post, byUser: byUser)
            player.play(sfx)
        }
        s.onLineComplete = {
            player.play(.lineVictory)
            // Persistence has already run by this point (attachProgressTracking
            // wraps this callback as its `priorComplete`). Fire confetti only
            // on the transition into learned, not on subsequent learned runs.
            if !wasLearnedAtSessionStart, line.mastery?.isLearned == true {
                confettiTrigger = Date()
            }
        }
        s.onIncorrectMove = { _, _ in player.play(.wrongMove) }
        // Wire persistence *after* the audio callbacks so the helper's
        // composition picks them up as the "prior" closures and still
        // fires them once persistence has run.
        s.attachProgressTracking(
            line: line,
            threshold: threshold,
            context: modelContext
        )
        audio = player
        session = s
        // Auto-restore the playout if we left one mid-game on this
        // line. The user must have completed the drill before the
        // playout could have started, so fast-forward the drill's
        // history to `.lineComplete` first — that way the move list
        // shows the drill prefix in front of the playout moves and
        // exiting playout lands the user back in a finished drill,
        // matching what they had before the relaunch.
        if let saved = persistedPlayouts.first(where: {
            $0.openingId == opening.id && $0.lineId == line.id
        }) {
            switch saved.phaseKind {
            case .playout:
                fastForwardDrillToCompletion(s)
                restorePlayout(from: saved)
            case .drill:
                restoreDrill(from: saved, into: s)
            }
        } else if opening.side == .black {
            scheduleBlackSideAutoplay(on: s)
        }
    }

    /// Resume a previously persisted drill session by replaying its
    /// move history into the freshly-built `DrillSession`. The session
    /// is the one already wired up by `startSessionIfNeeded` (audio +
    /// persistence callbacks attached), so after restore the user can
    /// keep drilling and every new move re-snapshots normally.
    /// No-op (and wipes the saved row) if the snapshot can't be
    /// reconstructed against the standard starting position.
    private func restoreDrill(
        from saved: PersistedPlayoutState,
        into s: DrillSession
    ) {
        guard let reconstructed = saved.moves.reconstruct(from: .standard) else {
            modelContext.delete(saved)
            try? modelContext.save()
            return
        }
        s.restore(history: reconstructed)
    }

    /// Silently replays every book ply into the drill session via
    /// `autoplayNextBookPly` so it sits in `.lineComplete`. Used when
    /// restoring a saved playout — the user already finished the
    /// drill in a prior session, no need to re-grade or re-sound it.
    private func fastForwardDrillToCompletion(_ s: DrillSession) {
        let priorMoveApplied = s.onMoveApplied
        let priorLineComplete = s.onLineComplete
        let priorIncorrect = s.onIncorrectMove
        s.onMoveApplied = nil
        s.onLineComplete = nil
        s.onIncorrectMove = nil
        while s.history.count < line.plies.count {
            s.autoplayNextBookPly()
        }
        s.onMoveApplied = priorMoveApplied
        s.onLineComplete = priorLineComplete
        s.onIncorrectMove = priorIncorrect
    }

    /// Tear-off entry to the engine playout. Builds an
    /// `EnginePlayoutSession` from the drill's final position + the
    /// user's side + chosen difficulty, reuses the existing
    /// `AudioService` for engine moves, and triggers bootstrap so
    /// Run the action the user just confirmed via the modal.
    private func executePendingConfirmation(_ kind: PlayoutConfirmation) {
        guard let p = playout else { return }
        switch kind {
        case .draw:
            Task { await p.offerDraw() }
        case .resign:
            p.resign()
        case .exit:
            clearPersistedPlayout()
            playout = nil
            moveAnnotation = nil
            precomputeTask?.cancel()
            precomputeTask = nil
            Task { await engineService?.shutdown() }
        }
    }

    /// engine-first openings (user-as-black) play white's first move
    /// immediately. The playout's own ui rendering ships in tasks
    /// 14-16; for now the state lives in `@State playout`.
    private func startPlayout(from s: DrillSession) {
        let svc = engineService ?? EngineService()
        engineService = svc
        let level = EngineLevel(rawSkill: settings?.engineLevel ?? 10)
        let session = EnginePlayoutSession(
            startingPosition: s.position,
            userSide: opening.side,
            level: level,
            engine: svc
        )
        wirePlayoutCallbacks(on: session)
        moveAnnotation = nil
        precomputeTask = nil
        playoutStartingFEN = s.position.fen
        playout = session
        snapshotPlayoutState()
        Task { await session.bootstrap() }
    }

    /// Resume a previously persisted playout. Builds the playout
    /// session at the saved starting position, silently replays the
    /// saved move history into it (no audio sfx, no engine queries),
    /// wires the live callbacks the way `startPlayout` does, then
    /// hands control back to the user (or kicks the engine straight
    /// into thinking if the saved state says it's the engine's turn).
    /// No-op if the snapshot can't be reconstructed against the
    /// starting position (corrupted state — wipe and start over).
    private func restorePlayout(from saved: PersistedPlayoutState) {
        guard let startingPos = Position(fen: saved.startingFEN) else {
            modelContext.delete(saved)
            try? modelContext.save()
            return
        }
        let userSide: Side = saved.userSideRaw == "black" ? .black : .white
        let level = EngineLevel(rawSkill: saved.engineLevel)
        let svc = engineService ?? EngineService()
        engineService = svc
        let session = EnginePlayoutSession(
            startingPosition: startingPos,
            userSide: userSide,
            level: level,
            engine: svc
        )
        guard let reconstructed = saved.moves.reconstruct(from: startingPos) else {
            modelContext.delete(saved)
            try? modelContext.save()
            return
        }
        session.restore(history: reconstructed)
        wirePlayoutCallbacks(on: session)
        moveAnnotation = nil
        precomputeTask = nil
        playoutStartingFEN = saved.startingFEN
        playout = session
        // Engine wake-up. For .engineThinking we play the reply
        // immediately; for .waitingForUser we run an explicit
        // precompute so the engine's NNUE setup is done before the
        // user makes their first move. Previously this only fired
        // through the `.onChange(of: userOnPlayoutClock, initial:true)`
        // path — which is fine in theory but the user saw cases
        // where the engine was still mid-warmup when the post-move
        // analyser awaited the precompute, leaving submit() blocked.
        if session.status == .engineThinking {
            Task { await session.bootstrap() }
        } else {
            schedulePlayoutPrecompute()
        }
    }

    /// Persist the playout snapshot for this line, creating a new
    /// `PersistedPlayoutState` row if needed. Called on every history
    /// change (incl. undo) so a relaunch puts the user back at the
    /// current ply. Cleared by `clearPersistedPlayout` on exit / game
    /// end.
    private func snapshotPlayoutState() {
        guard let p = playout, let startingFEN = playoutStartingFEN else { return }
        let stored = zip(p.history, p.historyByUser).map { (move, byUser) in
            StoredMove(move: move, byUser: byUser)
        }
        let data = (try? JSONEncoder().encode(stored)) ?? Data()
        let oid = opening.id
        let lid = line.id
        let existing = persistedPlayouts.first { $0.openingId == oid && $0.lineId == lid }
        if let existing {
            // a phase transition (drill → playout) reuses the row, so
            // bump phase too — otherwise the row would still resume
            // as a drill on next launch.
            existing.phase = PersistedPlayoutState.Phase.playout.rawValue
            existing.startingFEN = startingFEN
            existing.userSideRaw = opening.side == .black ? "black" : "white"
            existing.engineLevel = p.level.stockfishSkill
            existing.movesData = data
            existing.savedAt = Date()
        } else {
            let new = PersistedPlayoutState(
                openingId: oid,
                lineId: lid,
                startingFEN: startingFEN,
                userSideRaw: opening.side == .black ? "black" : "white",
                engineLevel: p.level.stockfishSkill,
                movesData: data,
                phase: .playout
            )
            modelContext.insert(new)
        }
        try? modelContext.save()
    }

    /// Persist the mid-drill snapshot for this line so a relaunch puts
    /// the user back at the current ply. Skipped while a playout is
    /// active (the playout snapshot is the source of truth then); if
    /// the drill history is empty (e.g. a reset), the saved row is
    /// deleted so the next launch lands on the opening list rather
    /// than auto-resuming a no-op.
    private func snapshotDrillState() {
        // playout snapshots take precedence — they're written by the
        // playout history watcher and supersede any drill row.
        guard playout == nil, let s = session else { return }
        let oid = opening.id
        let lid = line.id
        let existing = persistedPlayouts.first { $0.openingId == oid && $0.lineId == lid }
        if s.history.isEmpty {
            if let existing { modelContext.delete(existing) }
            try? modelContext.save()
            return
        }
        let stored = zip(s.history, s.historyByUser).map { (move, byUser) in
            StoredMove(move: move, byUser: byUser)
        }
        let data = (try? JSONEncoder().encode(stored)) ?? Data()
        let userSideRaw = opening.side == .black ? "black" : "white"
        let engineLevel = settings?.engineLevel ?? 10
        if let existing {
            existing.phase = PersistedPlayoutState.Phase.drill.rawValue
            existing.startingFEN = Position.standard.fen
            existing.userSideRaw = userSideRaw
            existing.engineLevel = engineLevel
            existing.movesData = data
            existing.savedAt = Date()
        } else {
            let new = PersistedPlayoutState(
                openingId: oid,
                lineId: lid,
                startingFEN: Position.standard.fen,
                userSideRaw: userSideRaw,
                engineLevel: engineLevel,
                movesData: data,
                phase: .drill
            )
            modelContext.insert(new)
        }
        try? modelContext.save()
    }

    /// Remove the persisted snapshot for this line (called when the
    /// user exits playout or the game ends — we don't want to resume
    /// into a finished game on next launch).
    private func clearPersistedPlayout() {
        let oid = opening.id
        let lid = line.id
        for state in persistedPlayouts where state.openingId == oid && state.lineId == lid {
            modelContext.delete(state)
        }
        try? modelContext.save()
    }

    /// Shared playout callback wiring used by `startPlayout` and
    /// `restorePlayout` so a restored session behaves the same as a
    /// freshly-started one.
    private func wirePlayoutCallbacks(on session: EnginePlayoutSession) {
        session.onMoveApplied = { [weak audio] move, pre, post, byUser in
            let sfx = SoundEffect.forMove(
                move, pre: pre, post: post, byUser: byUser
            )
            audio?.play(sfx)
        }
        session.onUserMoveAnalysing = { [weak engineService] move, pre, post in
            guard let svc = engineService else { return }
            let depth = settings?.moveAnalysisDepth ?? 10
            let budget = SearchBudget.depth(depth)

            let decision: EngineDecision?
            if let task = precomputeTask {
                let cached = await task.value
                if cached.position == pre, let d = cached.decision {
                    decision = d
                } else {
                    decision = await svc.bestMove(at: pre, skill: 20, budget: budget)
                }
            } else {
                decision = await svc.bestMove(at: pre, skill: 20, budget: budget)
            }

            let postEval = await svc.evaluate(at: post, budget: budget)
            let bestCp = decision?.evaluation?.clampedCp ?? 0
            let actualCp = -postEval.clampedCp
            let isWinning = bestCp >= 200
            let isBrilliant = isBrilliantCandidate(
                userMove: move, pre: pre, post: post,
                userSide: opening.side,
                bestUci: decision?.move.uci,
                bestEvalCp: bestCp,
                actualEvalCp: actualCp
            )
            let quality = MoveQuality.classify(
                bestEvalCp: bestCp,
                actualEvalCp: actualCp,
                bestEvalIsWinning: isWinning,
                isBrilliantCandidate: isBrilliant
            )
            moveAnnotation = MoveAnnotation(
                square: move.end,
                quality: quality,
                id: Date()
            )
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Whether the user is on the clock — used as the trigger for
    /// the bestmove precompute. Switches to true after bootstrap (for
    /// engine-first openings) and after every engine reply.
    private var userOnPlayoutClock: Bool {
        playout?.status == .waitingForUser
    }

    /// Whether the active playout reached a terminal state (mate,
    /// draw, resignation, etc.). Used to drive snapshot cleanup so a
    /// finished game isn't auto-resumed on next launch.
    private var playoutGameIsOver: Bool {
        if case .gameOver = playout?.status { return true }
        return false
    }

    /// Kicks off (or restarts) the bestmove precompute for the
    /// current playout position. Cancelling the existing task is a
    /// no-op against in-flight engine work (the call still completes
    /// on the queue), but ensures we don't await a stale result.
    private func schedulePlayoutPrecompute() {
        guard let p = playout, let svc = engineService else { return }
        let depth = settings?.moveAnalysisDepth ?? 10
        let pos = p.position
        precomputeTask?.cancel()
        precomputeTask = Task {
            let decision = await svc.bestMove(
                at: pos,
                skill: 20,
                budget: .depth(depth)
            )
            return (position: pos, decision: decision)
        }
    }

    /// For black-side openings, wait ~750ms after the board is shown before
    /// auto-playing white's first scripted move. Gives the user a moment to
    /// orient themselves instead of seeing white's move fly in on appear.
    private func scheduleBlackSideAutoplay(on s: DrillSession) {
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            s.autoplayNextBookPly()
        }
    }

    private func promptText(for s: DrillSession) -> String {
        switch s.status {
        case .waitingForUser:
            return "your move"
        case .evaluating:
            return "thinking..."
        case .mistake(let book, _):
            return "book says \(book.san) — try again"
        case .lineComplete:
            return "line complete ✓"
        }
    }

    private func promptColor(for s: DrillSession) -> Color {
        switch s.status {
        case .waitingForUser, .evaluating: return .primary
        case .mistake:                      return .red
        case .lineComplete:                 return .green
        }
    }

    private func sanLabel(ply: Int, san: String) -> String {
        // ply 0 is white's first move -> "1." prefix, ply 1 is black's -> no prefix
        if ply % 2 == 0 {
            return "\(ply / 2 + 1).\(san)"
        }
        return san
    }

    private func boardHighlights(for s: DrillSession) -> [Square: Set<HighlightKind>] {
        var map: [Square: Set<HighlightKind>] = [:]

        // Last move highlight follows whichever board is shown.
        if let p = playout, let last = p.history.last {
            map[last.start, default: []].insert(.lastMove)
            map[last.end, default: []].insert(.lastMove)
        } else if let last = s.lastAppliedMove {
            map[last.start, default: []].insert(.lastMove)
            map[last.end, default: []].insert(.lastMove)
        }

        if playout != nil {
            // Playout hint comes from stockfish at full strength: hint
            // pulses the source square; solution draws an arrow (handled
            // by `bestMoveArrow(for:)`) so no static square tints here.
            if hintShown, !solutionShown,
               let uci = playoutHint?.uci,
               let parsed = parsePlayoutHintUci(uci) {
                map[parsed.from, default: []].insert(.hintFromPulse)
            }
        } else {
            // Drill hint comes from the line book oracle. Same split:
            // hint = pulse, solution = arrow.
            if hintShown, !solutionShown,
               s.status != .lineComplete,
               s.history.count < line.plies.count,
               let move = SANParser.parse(move: line.plies[s.history.count].san, in: s.position) {
                map[move.start, default: []].insert(.hintFromPulse)
            }
            if case .mistake(let book, _) = s.status {
                map[book.move.start, default: []].insert(.hintFrom)
                map[book.move.end, default: []].insert(.hintTo)
            }
        }
        return map
    }

    /// Source/target squares for the solution arrow, or nil when the
    /// solution toggle is off or the underlying move can't be resolved.
    private func bestMoveArrow(for s: DrillSession) -> BoardView.BestMoveArrow? {
        guard solutionShown else { return nil }
        if playout != nil {
            guard let uci = playoutHint?.uci,
                  let parsed = parsePlayoutHintUci(uci) else { return nil }
            return BoardView.BestMoveArrow(from: parsed.from, to: parsed.to)
        }
        guard s.status != .lineComplete,
              s.history.count < line.plies.count,
              let move = SANParser.parse(move: line.plies[s.history.count].san,
                                         in: s.position) else { return nil }
        return BoardView.BestMoveArrow(from: move.start, to: move.end)
    }

    /// Asks stockfish at full strength for its preferred move in the
    /// current playout position and stores it for highlight rendering.
    /// Clears the cached hint when neither toggle is on, so stale
    /// highlights don't leak across positions.
    private func refreshPlayoutHintIfNeeded() {
        guard let p = playout, hintShown || solutionShown else {
            playoutHint = nil
            return
        }
        // hints only make sense while the user is on the clock —
        // not mid-engine-think, not at game end, not while a draw
        // modal is up.
        guard p.status == .waitingForUser else {
            playoutHint = nil
            return
        }
        guard let svc = engineService else { return }
        let pos = p.position
        Task {
            let decision = await svc.bestMove(
                at: pos,
                skill: 20,
                budget: .depth(12)
            )
            // discard the result if the position changed underneath
            // (user moved, or playout was exited) — a fresh refresh
            // task is already in flight for the new position.
            guard let current = playout, current.position == pos else {
                return
            }
            playoutHint = decision?.move
        }
    }

    private func parsePlayoutHintUci(_ uci: String) -> (from: Square, to: Square)? {
        guard uci.count >= 4 else { return nil }
        let fromStr = String(uci.prefix(2))
        let toStr = String(uci.dropFirst(2).prefix(2))
        guard isAlgebraic(fromStr), isAlgebraic(toStr) else { return nil }
        return (Square(fromStr), Square(toStr))
    }

    private func isAlgebraic(_ s: String) -> Bool {
        guard s.count == 2 else { return false }
        let chars = Array(s)
        return ("a"..."h").contains(chars[0]) && ("1"..."8").contains(chars[1])
    }
}
