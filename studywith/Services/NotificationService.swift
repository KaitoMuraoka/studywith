import Foundation
import UserNotifications

/// フェーズ終了のローカル通知を予約・取り消しする。
///
/// アプリがバックグラウンドにある間はタイマーの処理が動かないため、
/// 「作業終了」「休憩終了」をユーザーに知らせる手段はこの通知だけです（フェーズ1）。
///
/// メモ：アプリが前面にあるときは、通知は表示されません
/// （`UNUserNotificationCenterDelegate` を設定していないため）。
/// 前面では画面の表示が切り替わるので、サンプルではこれで十分としています。
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "pomodoro.phaseEnd."

    /// 通知の許可を求める。拒否されてもタイマー自体は動く。
    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("通知の許可リクエストに失敗: \(error)")
        }
    }

    /// 予定されているフェーズの終わりに通知を予約する。古い予約はすべて置き換える。
    func schedule(_ phaseEnds: [PhaseEnd], now: Date = .now) {
        cancelAll()
        for (index, phaseEnd) in phaseEnds.enumerated() {
            let interval = phaseEnd.date.timeIntervalSince(now)
            guard interval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = title(for: phaseEnd)
            content.body = body(for: phaseEnd)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(index),
                content: content,
                trigger: trigger
            )
            // 完了ハンドラ版を使うと、呼び出した順に登録されるので、
            // 「取り消し → 予約」が連続しても順番が入れ替わりません。
            center.add(request) { error in
                if let error {
                    print("通知の予約に失敗: \(error)")
                }
            }
        }
    }

    /// 予約済みの通知をすべて取り消す（一時停止・スキップ・リセット時）。
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private func title(for phaseEnd: PhaseEnd) -> String {
        switch phaseEnd.endingPhase {
        case .work: "作業時間が終わりました"
        case .shortBreak, .longBreak: "休憩時間が終わりました"
        }
    }

    private func body(for phaseEnd: PhaseEnd) -> String {
        switch phaseEnd.nextPhase {
        case .work:
            "作業を再開しましょう。アプリを開くと音楽が再開します。"
        case .shortBreak, .longBreak:
            // フェーズ1では、アプリが裏にあると音楽を止められない（AlarmKit 連携はフェーズ2）。
            "\(phaseEnd.nextPhase.displayName)です。アプリを開くと音楽が一時停止します。"
        }
    }
}
