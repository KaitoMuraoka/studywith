import Foundation
import MusicKit
import Observation
import UIKit

/// 画面とロジックをつなぐクラス。
///
/// 純粋なロジック（`PomodoroEngine`）に操作を伝え、状態が変わったら
/// 「音楽」「通知」「画面スリープ」の副作用をまとめて反映します。
///
/// 副作用のルールはシンプルに1つだけです：
/// - 作業フェーズが動いている間 → 音楽を流す・画面スリープを止める
/// - それ以外（待機・休憩・一時停止）→ 音楽を一時停止・画面スリープを戻す
@Observable
final class PomodoroController {
    private(set) var engine: PomodoroEngine
    /// 画面表示用の「現在時刻」。1秒ごとに更新され、残り時間の再計算を促す。
    private(set) var now: Date = .now

    let music: MusicService
    private let notifications: NotificationService

    /// 1秒ごとに時刻を進めるタスク。
    /// バックグラウンドではアプリごと止まるので、復帰時の補正は `sceneDidBecomeActive()` で行う。
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    var settings: PomodoroSettings {
        get { engine.settings }
        set {
            engine.settings = newValue
            newValue.save()
            // 長さが変わると、この先のフェーズの終了時刻が変わるので通知を予約し直す。
            // （今動いているフェーズの終了時刻は変えない）
            rescheduleNotifications()
        }
    }

    var state: TimerState { engine.state }
    var remainingTime: TimeInterval { engine.remainingTime(at: now) }
    var progress: Double { engine.progress(at: now) }
    var currentCycle: Int { engine.currentCycle }

    init(
        music: MusicService = MusicService(),
        notifications: NotificationService = NotificationService(),
        settings: PomodoroSettings = .load()
    ) {
        self.music = music
        self.notifications = notifications
        self.engine = PomodoroEngine(settings: settings)
        startTicking()
    }

    // MARK: - 起動時

    func requestNotificationAuthorization() async {
        await notifications.requestAuthorization()
    }

    // MARK: - ユーザー操作

    func start() { perform { $0.start(at: now) } }
    func pause() { perform { $0.pause(at: now) } }
    func resume() { perform { $0.resume(at: now) } }
    func skip() { perform { $0.skip(at: now) } }
    func reset() { perform { $0.reset() } }

    /// プレイリストを選んだとき。作業中ならすぐに新しいプレイリストに切り替える。
    func select(_ playlist: Playlist) {
        music.select(playlist)
        if engine.state.isWorkRunning {
            Task { await music.playForWork() }
        }
    }

    // MARK: - 時間経過

    /// scenePhase が active になったときに呼ぶ。
    /// バックグラウンドにいた間に終了時刻を過ぎていれば、正しいフェーズまで進める。
    /// 作業時間が過ぎていれば、ここで音楽が一時停止される。
    func sceneDidBecomeActive() {
        now = .now
        let before = engine.state
        if engine.advanceIfNeeded(at: now) {
            applySideEffects(from: before)
        }
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        now = .now
        let before = engine.state
        if engine.advanceIfNeeded(at: now) {
            applySideEffects(from: before)
        }
    }

    // MARK: - 副作用

    /// エンジンを操作し、状態が変わっていれば副作用を反映する。
    private func perform(_ action: (inout PomodoroEngine) -> Void) {
        now = .now
        let before = engine.state
        action(&engine)
        if engine.state != before {
            applySideEffects(from: before)
        }
    }

    private func applySideEffects(from before: TimerState) {
        let wasWorking = before.isWorkRunning
        let isWorking = engine.state.isWorkRunning

        // 1. 音楽：作業の開始・終了が切り替わったときだけ操作する
        if !wasWorking && isWorking {
            Task { await music.playForWork() }
        } else if wasWorking && !isWorking {
            music.pauseForBreak()
        }

        // 2. 画面スリープ：作業中だけ止める
        UIApplication.shared.isIdleTimerDisabled = isWorking

        // 3. 通知：一時停止・スキップ・リセットを含め、状態が変わるたびに予約し直す
        rescheduleNotifications()
    }

    private func rescheduleNotifications() {
        guard engine.state.isRunning else {
            notifications.cancelAll()
            return
        }
        // 長い休憩までの1セット分（作業＋休憩 × サイクル数）を先まで予約しておく。
        // アプリを開かないまま次のフェーズに入っても通知が届くようにするため。
        // （iOS の予約上限は64件なので、それより十分少ない数にしている）
        let limit = engine.settings.cyclesBeforeLongBreak * 2
        notifications.schedule(engine.upcomingPhaseEnds(limit: limit), now: now)
    }
}
