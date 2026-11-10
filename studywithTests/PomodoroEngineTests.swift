import Foundation
import Testing
@testable import studywith

/// タイマーのロジック（状態遷移と残り時間の計算）のテスト。
/// 現在時刻を引数で渡せるので、待たずに「25分後」などを再現できる。
struct PomodoroEngineTests {
    /// 基準時刻（固定）
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    let minute: TimeInterval = 60

    func makeEngine(work: Int = 25, short: Int = 5, long: Int = 15, cycles: Int = 4) -> PomodoroEngine {
        PomodoroEngine(settings: PomodoroSettings(
            workMinutes: work,
            shortBreakMinutes: short,
            longBreakMinutes: long,
            cyclesBeforeLongBreak: cycles
        ))
    }

    // MARK: - 初期状態

    @Test func 初期状態は待機中で残り時間は作業時間() {
        let engine = makeEngine()
        #expect(engine.state == .idle)
        #expect(engine.remainingTime(at: t0) == 25 * minute)
        #expect(engine.currentCycle == 1)
        #expect(engine.progress(at: t0) == 0)
    }

    @Test func 設定の初期値() {
        let settings = PomodoroSettings.default
        #expect(settings.workMinutes == 25)
        #expect(settings.shortBreakMinutes == 5)
        #expect(settings.longBreakMinutes == 15)
        #expect(settings.cyclesBeforeLongBreak == 4)
    }

    // MARK: - 開始と残り時間

    @Test func 開始すると作業中になり終了時刻が保存される() {
        var engine = makeEngine()
        engine.start(at: t0)
        #expect(engine.state == .work(endDate: t0 + 25 * minute))
    }

    @Test func 残り時間は終了時刻と現在時刻の差で計算される() {
        var engine = makeEngine()
        engine.start(at: t0)
        #expect(engine.remainingTime(at: t0 + 10 * minute) == 15 * minute)
        #expect(abs(engine.progress(at: t0 + 10 * minute) - 0.4) < 0.000001)
    }

    @Test func 残り時間はマイナスにならない() {
        var engine = makeEngine()
        engine.start(at: t0)
        #expect(engine.remainingTime(at: t0 + 30 * minute) == 0)
    }

    @Test func 動作中に開始を押しても何も起きない() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.start(at: t0 + minute)
        #expect(engine.state == .work(endDate: t0 + 25 * minute))
    }

    // MARK: - 一時停止と再開

    @Test func 一時停止すると残り時間が固定される() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.pause(at: t0 + 10 * minute)
        #expect(engine.state == .paused(phase: .work, remaining: 15 * minute))
        // 時間がたっても残り時間は変わらない
        #expect(engine.remainingTime(at: t0 + 100 * minute) == 15 * minute)
    }

    @Test func 一時停止中は時間がたってもフェーズが進まない() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.pause(at: t0 + 10 * minute)
        let advanced = engine.advanceIfNeeded(at: t0 + 100 * minute)
        #expect(advanced == false)
        #expect(engine.state == .paused(phase: .work, remaining: 15 * minute))
    }

    @Test func 再開すると残り時間から新しい終了時刻が決まる() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.pause(at: t0 + 10 * minute)
        engine.resume(at: t0 + 20 * minute)
        #expect(engine.state == .work(endDate: t0 + 35 * minute))
    }

    @Test func 待機中に一時停止や再開をしても何も起きない() {
        var engine = makeEngine()
        engine.pause(at: t0)
        engine.resume(at: t0)
        engine.skip(at: t0)
        #expect(engine.state == .idle)
    }

    // MARK: - 時間経過による遷移

    @Test func 作業が終わると短い休憩になる() {
        var engine = makeEngine()
        engine.start(at: t0)
        let advanced = engine.advanceIfNeeded(at: t0 + 25 * minute)
        #expect(advanced)
        #expect(engine.state == .shortBreak(endDate: t0 + 30 * minute))
        #expect(engine.completedWorkSessions == 1)
        #expect(engine.currentCycle == 1)
    }

    @Test func 終了時刻前は遷移しない() {
        var engine = makeEngine()
        engine.start(at: t0)
        let advanced = engine.advanceIfNeeded(at: t0 + 25 * minute - 1)
        #expect(advanced == false)
        #expect(engine.state.isWorkRunning)
    }

    @Test func 休憩が終わると次の作業になりサイクルが進む() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.advanceIfNeeded(at: t0 + 25 * minute)
        engine.advanceIfNeeded(at: t0 + 30 * minute)
        #expect(engine.state == .work(endDate: t0 + 55 * minute))
        #expect(engine.currentCycle == 2)
    }

    @Test func 指定サイクルごとに長い休憩になる() {
        var engine = makeEngine(cycles: 4)
        engine.start(at: t0)
        // 作業25分 + 短い休憩5分 = 30分 を3回、その後4回目の作業25分
        let fourthWorkEnd = t0 + (30 * 3 + 25) * minute
        engine.advanceIfNeeded(at: fourthWorkEnd)
        #expect(engine.state == .longBreak(endDate: fourthWorkEnd + 15 * minute))
        #expect(engine.completedWorkSessions == 4)
        #expect(engine.currentCycle == 4)

        // 長い休憩の後は、サイクル1に戻る
        engine.advanceIfNeeded(at: fourthWorkEnd + 15 * minute)
        #expect(engine.state.isWorkRunning)
        #expect(engine.currentCycle == 1)
    }

    @Test func バックグラウンド復帰時は複数フェーズまとめて追いつく() {
        var engine = makeEngine()
        engine.start(at: t0)
        // 40分後に戻ってきた：作業(0-25) → 短い休憩(25-30) → 作業(30-55) の途中
        engine.advanceIfNeeded(at: t0 + 40 * minute)
        #expect(engine.state == .work(endDate: t0 + 55 * minute))
        #expect(engine.remainingTime(at: t0 + 40 * minute) == 15 * minute)
        #expect(engine.currentCycle == 2)
    }

    @Test func 次のフェーズは前のフェーズの終了時刻から始まる() {
        var engine = makeEngine()
        engine.start(at: t0)
        // 作業終了の1分後に気づいても、休憩は作業の終了時刻から数える
        engine.advanceIfNeeded(at: t0 + 26 * minute)
        #expect(engine.state == .shortBreak(endDate: t0 + 30 * minute))
        #expect(engine.remainingTime(at: t0 + 26 * minute) == 4 * minute)
    }

    // MARK: - スキップとリセット

    @Test func 作業をスキップすると休憩がすぐ始まり作業回数に数える() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.skip(at: t0 + 5 * minute)
        #expect(engine.state == .shortBreak(endDate: t0 + 10 * minute))
        #expect(engine.completedWorkSessions == 1)
    }

    @Test func 休憩をスキップすると作業がすぐ始まる() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.skip(at: t0)
        engine.skip(at: t0 + minute)
        #expect(engine.state == .work(endDate: t0 + 26 * minute))
    }

    @Test func 一時停止中にスキップすると次のフェーズが動作中で始まる() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.pause(at: t0 + minute)
        engine.skip(at: t0 + 2 * minute)
        #expect(engine.state == .shortBreak(endDate: t0 + 7 * minute))
    }

    @Test func リセットすると待機中に戻り作業回数も0になる() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.skip(at: t0)
        engine.reset()
        #expect(engine.state == .idle)
        #expect(engine.completedWorkSessions == 0)
        #expect(engine.currentCycle == 1)
    }

    // MARK: - 設定の変更

    @Test func 設定の変更は次のフェーズから反映される() {
        var engine = makeEngine()
        engine.start(at: t0)
        engine.settings.shortBreakMinutes = 10
        // 今の作業の終了時刻は変わらない
        #expect(engine.state == .work(endDate: t0 + 25 * minute))
        engine.advanceIfNeeded(at: t0 + 25 * minute)
        #expect(engine.state == .shortBreak(endDate: t0 + 35 * minute))
    }

    @Test func 長さが0分以下でも最低1分として扱う() {
        let settings = PomodoroSettings(workMinutes: 0, shortBreakMinutes: -3, longBreakMinutes: 15, cyclesBeforeLongBreak: 4)
        #expect(settings.duration(of: .work) == minute)
        #expect(settings.duration(of: .shortBreak) == minute)
    }

    // MARK: - 通知用の予定

    @Test func この先のフェーズの終わりを列挙できる() {
        var engine = makeEngine(cycles: 2)
        engine.start(at: t0)
        let ends = engine.upcomingPhaseEnds(limit: 4)
        #expect(ends == [
            PhaseEnd(endingPhase: .work, date: t0 + 25 * minute, nextPhase: .shortBreak),
            PhaseEnd(endingPhase: .shortBreak, date: t0 + 30 * minute, nextPhase: .work),
            PhaseEnd(endingPhase: .work, date: t0 + 55 * minute, nextPhase: .longBreak),
            PhaseEnd(endingPhase: .longBreak, date: t0 + 70 * minute, nextPhase: .work),
        ])
        // 試算しても自分自身の状態は変わらない
        #expect(engine.state == .work(endDate: t0 + 25 * minute))
        #expect(engine.completedWorkSessions == 0)
    }

    @Test func 動作中でなければ予定は空() {
        var engine = makeEngine()
        #expect(engine.upcomingPhaseEnds(limit: 4).isEmpty)
        engine.start(at: t0)
        engine.pause(at: t0)
        #expect(engine.upcomingPhaseEnds(limit: 4).isEmpty)
    }

    // MARK: - 状態のヘルパー

    @Test func 音楽を流すのは作業が動いているときだけ() {
        #expect(TimerState.idle.isWorkRunning == false)
        #expect(TimerState.work(endDate: t0).isWorkRunning)
        #expect(TimerState.shortBreak(endDate: t0).isWorkRunning == false)
        #expect(TimerState.longBreak(endDate: t0).isWorkRunning == false)
        #expect(TimerState.paused(phase: .work, remaining: 60).isWorkRunning == false)
    }
}
