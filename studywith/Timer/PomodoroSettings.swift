import Foundation

/// ユーザーが設定画面で変えられる値。
nonisolated struct PomodoroSettings: Codable, Equatable, Sendable {
    var workMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    /// 何回作業したら長い休憩にするか
    var cyclesBeforeLongBreak: Int = 4

    static let `default` = PomodoroSettings()

    /// 設定画面で選べる範囲
    static let minutesRange = 1...90
    static let cyclesRange = 2...8

    /// フェーズの長さ（秒）
    func duration(of phase: Phase) -> TimeInterval {
        let minutes = switch phase {
        case .work: workMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        // 0分以下だとフェーズが永遠に終わり続けるので、最低1分にする。
        return TimeInterval(max(1, minutes) * 60)
    }
}

// MARK: - 保存と読み込み

extension PomodoroSettings {
    private static let userDefaultsKey = "PomodoroSettings"

    /// UserDefaults から読み込む。保存されていなければ初期値。
    static func load(from defaults: UserDefaults = .standard) -> PomodoroSettings {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(PomodoroSettings.self, from: data)
        else { return .default }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }
}
