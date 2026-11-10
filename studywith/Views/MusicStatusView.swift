import MusicKit
import SwiftUI
import UIKit

/// Apple Music が使えない理由と、その対処を案内する帯。
/// 使える状態でプレイリストも選んであれば何も表示しない。
struct MusicStatusView: View {
    @Environment(MusicService.self) private var music
    @Environment(\.openURL) private var openURL
    @State private var isShowingSubscriptionOffer = false

    /// 「プレイリストを選ぶ」が押されたとき
    let onPickPlaylist: @MainActor () -> Void

    var body: some View {
        content
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 未加入ユーザーに Apple Music の加入（トライアル）を案内するシート
            .musicSubscriptionOffer(isPresented: $isShowingSubscriptionOffer, options: subscriptionOfferOptions)
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { music.errorMessage != nil },
                    set: { if !$0 { music.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(music.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch music.availability {
        case .checking:
            ProgressView("Apple Music の状態を確認しています")

        case .notDetermined:
            banner("音楽を流すには Apple Music へのアクセスを許可してください。") {
                Button("許可する") {
                    Task { await music.requestAuthorization() }
                }
            }

        case .denied:
            banner("Apple Music へのアクセスが許可されていません。設定アプリの「StudyWith」→「メディアとApple Music」をオンにしてください。タイマーは音楽なしで使えます。") {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }

        case .restricted:
            banner("この端末では Apple Music の利用が制限されています。タイマーは音楽なしで使えます。") {
                EmptyView()
            }

        case .cannotPlayCatalog(let canBecomeSubscriber):
            banner("Apple Music に加入していないため、音楽機能は使えません。タイマーは音楽なしで使えます。") {
                if canBecomeSubscriber {
                    Button("Apple Music を試す") {
                        isShowingSubscriptionOffer = true
                    }
                }
            }

        case .available:
            if music.selectedPlaylist == nil {
                banner("作業中に流すプレイリストを選んでください。") {
                    Button("プレイリストを選ぶ", action: onPickPlaylist)
                }
            }
        }
    }

    private var subscriptionOfferOptions: MusicSubscriptionOffer.Options {
        var options = MusicSubscriptionOffer.Options.default
        // 「音楽を再生するために加入する」という文言のシートにする
        options.messageIdentifier = .playMusic
        return options
    }

    private func banner<Action: View>(_ message: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "music.note")
            action()
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 12))
    }
}
