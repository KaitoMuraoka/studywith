import SwiftUI

/// メイン画面：残り時間、フェーズ、サイクル、操作ボタン、再生中の曲。
struct MainView: View {
    @Environment(PomodoroController.self) private var controller
    @State private var isShowingSettings = false
    @State private var isShowingPlaylistPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                MusicStatusView(onPickPlaylist: { isShowingPlaylistPicker = true })

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Text(controller.state.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(phaseColor)
                    Text("サイクル \(controller.currentCycle) / \(controller.settings.cyclesBeforeLongBreak)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TimerRingView(
                    progress: controller.progress,
                    remainingTime: controller.remainingTime,
                    color: phaseColor
                )

                ControlButtons()

                Spacer(minLength: 0)

                NowPlayingView()
            }
            .padding()
            .navigationTitle("StudyWith")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("プレイリスト", systemImage: "music.note.list") {
                        isShowingPlaylistPicker = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("設定", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingPlaylistPicker) {
                PlaylistPickerView()
            }
        }
    }

    private var phaseColor: Color {
        switch controller.state.phase {
        case .work: .red
        case .shortBreak: .green
        case .longBreak: .blue
        case nil: .secondary
        }
    }
}

/// 残り時間を大きく表示するリング。
private struct TimerRingView: View {
    let progress: Double
    let remainingTime: TimeInterval
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text(Self.format(remainingTime))
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: 260, height: 260)
    }

    /// 秒を「mm:ss」にする。端数は切り上げる（残り0.4秒を 00:00 と出さないため）。
    static func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 状態に応じて出し分ける操作ボタン。
private struct ControlButtons: View {
    @Environment(PomodoroController.self) private var controller

    var body: some View {
        HStack(spacing: 16) {
            switch controller.state {
            case .idle:
                Button("開始", systemImage: "play.fill", action: controller.start)
                    .buttonStyle(.borderedProminent)
            case .work, .shortBreak, .longBreak:
                Button("一時停止", systemImage: "pause.fill", action: controller.pause)
                    .buttonStyle(.borderedProminent)
                secondaryButtons
            case .paused:
                Button("再開", systemImage: "play.fill", action: controller.resume)
                    .buttonStyle(.borderedProminent)
                secondaryButtons
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button("スキップ", systemImage: "forward.end.fill", action: controller.skip)
            .buttonStyle(.bordered)
        Button("リセット", systemImage: "arrow.counterclockwise", role: .destructive, action: controller.reset)
            .buttonStyle(.bordered)
    }
}

#Preview {
    let controller = PomodoroController()
    MainView()
        .environment(controller)
        .environment(controller.music)
}
