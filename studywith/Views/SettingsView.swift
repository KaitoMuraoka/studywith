import SwiftUI

/// 設定画面：各フェーズの長さと、長い休憩までのサイクル数。
///
/// 変更は次に始まるフェーズから反映されます（今動いているフェーズの終了時刻は変わりません）。
struct SettingsView: View {
    @Environment(PomodoroController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // @Environment で受け取った @Observable オブジェクトから Binding を作るには @Bindable を使う
        @Bindable var controller = controller

        NavigationStack {
            Form {
                Section {
                    Stepper(value: $controller.settings.workMinutes, in: PomodoroSettings.minutesRange) {
                        LabeledContent("作業", value: "\(controller.settings.workMinutes) 分")
                    }
                    Stepper(value: $controller.settings.shortBreakMinutes, in: PomodoroSettings.minutesRange) {
                        LabeledContent("短い休憩", value: "\(controller.settings.shortBreakMinutes) 分")
                    }
                    Stepper(value: $controller.settings.longBreakMinutes, in: PomodoroSettings.minutesRange) {
                        LabeledContent("長い休憩", value: "\(controller.settings.longBreakMinutes) 分")
                    }
                } header: {
                    Text("時間")
                } footer: {
                    Text("変更は次のフェーズから反映されます。")
                }

                Section("サイクル") {
                    Stepper(value: $controller.settings.cyclesBeforeLongBreak, in: PomodoroSettings.cyclesRange) {
                        LabeledContent("長い休憩までの作業回数", value: "\(controller.settings.cyclesBeforeLongBreak) 回")
                    }
                }

                Section {
                    Button("初期値に戻す") {
                        controller.settings = .default
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}
