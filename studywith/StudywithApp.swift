import SwiftUI

@main
struct StudywithApp: App {
    /// アプリ全体で1つだけ持つコントローラー。
    /// `@Observable` のクラスは `@State` で保持する（Observation フレームワークの作法）。
    @State private var controller = PomodoroController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(controller)
                .environment(controller.music)
                .task {
                    // 起動時に通知と Apple Music の許可を求める。
                    // music.start() は加入状況の監視を続けるため、最後に呼ぶ。
                    await controller.requestNotificationAuthorization()
                    await controller.music.start()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // バックグラウンドから戻ったら、現在時刻と終了時刻を比べて状態を補正する。
            if newPhase == .active {
                controller.sceneDidBecomeActive()
            }
        }
    }
}
