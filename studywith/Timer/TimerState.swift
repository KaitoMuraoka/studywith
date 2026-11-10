import Foundation

/// ポモドーロの「フェーズ」（作業か休憩か）。
///
/// `nonisolated` を付けているのは、このプロジェクトが
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` になっているためです。
/// 付けないと型が MainActor に隔離され、ユニットテストから扱いにくくなります。
nonisolated enum Phase: String, Codable, Equatable, Sendable {
    case work
    case shortBreak
    case longBreak

    var displayName: String {
        switch self {
        case .work: "作業中"
        case .shortBreak: "短い休憩"
        case .longBreak: "長い休憩"
        }
    }

    var isBreak: Bool { self != .work }
}

/// タイマーの状態。要件の5状態をそのまま enum で表します。
///
/// 動いている状態は「残り秒数」ではなく「終了時刻 (endDate)」を持ちます。
/// 残り時間は `endDate - 現在時刻` で毎回計算するので、
/// アプリがバックグラウンドで止まっていても、戻ったときに正しい値になります。
nonisolated enum TimerState: Equatable, Sendable {
    /// 待機中（まだ始めていない、またはリセットした）
    case idle
    /// 作業中
    case work(endDate: Date)
    /// 短い休憩
    case shortBreak(endDate: Date)
    /// 長い休憩
    case longBreak(endDate: Date)
    /// 一時停止中。どのフェーズを止めたかと、止めた時点の残り時間を持つ。
    case paused(phase: Phase, remaining: TimeInterval)

    /// 動作中（一時停止ではない）フェーズを作る。
    static func running(_ phase: Phase, endDate: Date) -> TimerState {
        switch phase {
        case .work: .work(endDate: endDate)
        case .shortBreak: .shortBreak(endDate: endDate)
        case .longBreak: .longBreak(endDate: endDate)
        }
    }

    /// 現在のフェーズ。一時停止中は止めたフェーズを返す。待機中は nil。
    var phase: Phase? {
        switch self {
        case .idle: nil
        case .work: .work
        case .shortBreak: .shortBreak
        case .longBreak: .longBreak
        case .paused(let phase, _): phase
        }
    }

    /// 動作中のフェーズの終了時刻。待機中と一時停止中は nil。
    var endDate: Date? {
        switch self {
        case .work(let endDate), .shortBreak(let endDate), .longBreak(let endDate): endDate
        case .idle, .paused: nil
        }
    }

    /// カウントダウンが進んでいるか。
    var isRunning: Bool { endDate != nil }

    /// 作業フェーズのカウントダウンが進んでいるか。
    /// 「音楽を流す」「画面スリープを止める」の判定に使う。
    var isWorkRunning: Bool {
        if case .work = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .idle: "待機中"
        case .paused: "一時停止中"
        case .work, .shortBreak, .longBreak: phase?.displayName ?? ""
        }
    }
}
