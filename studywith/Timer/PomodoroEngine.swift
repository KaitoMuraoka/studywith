import Foundation

/// フェーズの終わり1回分の予定。通知の予約に使う。
nonisolated struct PhaseEnd: Equatable, Sendable {
    /// 終わるフェーズ
    let endingPhase: Phase
    /// 終わる時刻
    let date: Date
    /// 次に始まるフェーズ
    let nextPhase: Phase
}

/// ポモドーロタイマーの純粋なロジック。
///
/// - UI、MusicKit、通知、`Timer` には一切依存しません。
/// - 「現在時刻」は引数 `now` で外から渡します。
///   そのためユニットテストでは好きな時刻を渡して、状態遷移と残り時間を確かめられます。
/// - 値型 (struct) なので、コピーして「この先どうなるか」を試算することもできます
///   （`upcomingPhaseEnds` で使っています）。
nonisolated struct PomodoroEngine: Equatable, Sendable {
    var settings: PomodoroSettings
    private(set) var state: TimerState = .idle
    /// 終えた作業フェーズの数（スキップした作業も含む）。長い休憩の判定に使う。
    private(set) var completedWorkSessions: Int = 0

    init(settings: PomodoroSettings = .default) {
        self.settings = settings
    }

    // MARK: - 表示用の値

    /// 残り時間（秒）。
    func remainingTime(at now: Date) -> TimeInterval {
        switch state {
        case .idle:
            settings.duration(of: .work)
        case .paused(_, let remaining):
            remaining
        case .work(let endDate), .shortBreak(let endDate), .longBreak(let endDate):
            max(0, endDate.timeIntervalSince(now))
        }
    }

    /// 進み具合 (0.0〜1.0)。リング表示に使う。
    func progress(at now: Date) -> Double {
        guard let phase = state.phase else { return 0 }
        let total = settings.duration(of: phase)
        return min(1, max(0, 1 - remainingTime(at: now) / total))
    }

    /// 長い休憩までのうち、いま何サイクル目か（1始まり）。
    var currentCycle: Int {
        let cycles = max(1, settings.cyclesBeforeLongBreak)
        switch state.phase {
        case .none, .work:
            // これから（または今）行う作業が何回目か
            return completedWorkSessions % cycles + 1
        case .shortBreak, .longBreak:
            // 休憩中は、直前に終えた作業が何回目だったか
            return (completedWorkSessions - 1) % cycles + 1
        }
    }

    // MARK: - ユーザー操作

    /// 開始：待機中 → 作業中
    mutating func start(at now: Date) {
        guard state == .idle else { return }
        begin(.work, at: now)
    }

    /// 一時停止：動作中 → 一時停止中
    mutating func pause(at now: Date) {
        guard let phase = state.phase, state.isRunning else { return }
        state = .paused(phase: phase, remaining: remainingTime(at: now))
    }

    /// 再開：一時停止中 → 止めたフェーズ
    mutating func resume(at now: Date) {
        guard case .paused(let phase, let remaining) = state else { return }
        state = .running(phase, endDate: now.addingTimeInterval(remaining))
    }

    /// スキップ：今のフェーズを終わらせて、次のフェーズをすぐ始める。
    /// 一時停止中にスキップした場合も、次のフェーズは動作中で始まる。
    mutating func skip(at now: Date) {
        guard let phase = state.phase else { return }
        moveToNextPhase(after: phase, startingAt: now)
    }

    /// リセット：すべて最初に戻す。
    mutating func reset() {
        state = .idle
        completedWorkSessions = 0
    }

    // MARK: - 時間経過

    /// 終了時刻を過ぎたフェーズを、次のフェーズへ進める。
    ///
    /// バックグラウンドから戻ったときは、複数のフェーズが終わっていることがあります。
    /// そのため、追いつくまでループします。次のフェーズの開始時刻は `now` ではなく
    /// 「前のフェーズの終了時刻」にするので、時間の流れがずれません。
    ///
    /// - Returns: フェーズが1つでも進んだら true
    @discardableResult
    mutating func advanceIfNeeded(at now: Date) -> Bool {
        var advanced = false
        while let endDate = state.endDate, let phase = state.phase, endDate <= now {
            moveToNextPhase(after: phase, startingAt: endDate)
            advanced = true
        }
        return advanced
    }

    /// この先に予定されているフェーズの終わりを、最大 `limit` 件返す。
    /// 動作中でなければ空。通知をまとめて予約するために使う。
    func upcomingPhaseEnds(limit: Int) -> [PhaseEnd] {
        var simulation = self   // 値型なので自分自身は変わらない
        var result: [PhaseEnd] = []
        while result.count < limit, let endDate = simulation.state.endDate, let phase = simulation.state.phase {
            simulation.moveToNextPhase(after: phase, startingAt: endDate)
            // moveToNextPhase の後なので、state.phase は必ず次のフェーズ
            guard let next = simulation.state.phase else { break }
            result.append(PhaseEnd(endingPhase: phase, date: endDate, nextPhase: next))
        }
        return result
    }

    // MARK: - 内部処理

    /// `phase` が終わったときに次に来るフェーズ。作業の回数もここで数える。
    private mutating func moveToNextPhase(after phase: Phase, startingAt start: Date) {
        switch phase {
        case .work:
            completedWorkSessions += 1
            let cycles = max(1, settings.cyclesBeforeLongBreak)
            let isLongBreak = completedWorkSessions % cycles == 0
            begin(isLongBreak ? .longBreak : .shortBreak, at: start)
        case .shortBreak, .longBreak:
            begin(.work, at: start)
        }
    }

    private mutating func begin(_ phase: Phase, at start: Date) {
        state = .running(phase, endDate: start.addingTimeInterval(settings.duration(of: phase)))
    }
}
