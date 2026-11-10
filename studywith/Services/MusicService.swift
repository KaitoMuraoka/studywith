import Foundation
import MusicKit
import Observation

/// Apple Music まわりの処理をまとめたクラス。
///
/// - 許可（MusicAuthorization）と加入状況（MusicSubscription）の管理
/// - プレイリストの取得（ライブラリ / カタログ検索）
/// - `ApplicationMusicPlayer` での再生・一時停止
///
/// `ApplicationMusicPlayer` はアプリ専用のプレイヤーで、ミュージックアプリの
/// 再生キューや再生状態には影響しません（`SystemMusicPlayer` は使わない）。
@Observable
final class MusicService {

    /// 音楽機能が使えるかどうか。画面の案内表示に使う。
    enum Availability: Equatable {
        /// 確認中
        case checking
        /// まだ許可を求めていない
        case notDetermined
        /// ユーザーが拒否した
        case denied
        /// ペアレンタルコントロールなどで制限されている
        case restricted
        /// Apple Music のカタログを再生できない（未加入など）
        case cannotPlayCatalog(canBecomeSubscriber: Bool)
        /// 使える
        case available
    }

    private(set) var authorizationStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    private(set) var subscription: MusicSubscription?
    /// 作業中に流すプレイリスト
    private(set) var selectedPlaylist: Playlist?
    /// 直近のエラー（画面に表示する）
    var errorMessage: String?

    /// 今プレイヤーのキューに入っているプレイリストの ID。
    /// 同じプレイリストなら `play()` だけで続きから再開するために覚えておく。
    private var queuedPlaylistID: MusicItemID?

    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }

    var availability: Availability {
        switch authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: break
        @unknown default: return .denied
        }
        guard let subscription else { return .checking }
        guard subscription.canPlayCatalogContent else {
            return .cannotPlayCatalog(canBecomeSubscriber: subscription.canBecomeSubscriber)
        }
        return .available
    }

    var canPlayMusic: Bool { availability == .available }

    // MARK: - 許可と加入状況

    /// 起動時に呼ぶ。許可を求め、加入状況の監視を始める。
    /// この関数は加入状況の監視が続く間は戻らないので、`.task { }` から呼ぶこと。
    func start() async {
        if authorizationStatus == .notDetermined {
            authorizationStatus = await MusicAuthorization.request()
        }
        guard authorizationStatus == .authorized else { return }

        // まず現在の加入状況を取得する。
        do {
            subscription = try await MusicSubscription.current
        } catch {
            errorMessage = "Apple Music の加入状況を確認できませんでした：\(error.localizedDescription)"
        }

        // 加入（トライアル開始）や解約で状況が変わったら追従する。
        for await update in MusicSubscription.subscriptionUpdates {
            subscription = update
        }
    }

    /// 許可ダイアログを再表示したいとき用（notDetermined のときだけ効く）。
    func requestAuthorization() async {
        authorizationStatus = await MusicAuthorization.request()
    }

    // MARK: - プレイリストの取得

    /// ユーザーのライブラリにあるプレイリスト
    func fetchLibraryPlaylists() async throws -> MusicItemCollection<Playlist> {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        let response = try await request.response()
        return response.items
    }

    /// Apple Music カタログからプレイリストを検索する
    func searchCatalogPlaylists(term: String) async throws -> MusicItemCollection<Playlist> {
        var request = MusicCatalogSearchRequest(term: term, types: [Playlist.self])
        request.limit = 25
        let response = try await request.response()
        return response.playlists
    }

    func select(_ playlist: Playlist) {
        selectedPlaylist = playlist
    }

    // MARK: - 再生と一時停止

    /// 作業開始時に呼ぶ。
    /// - 初回（またはプレイリストを変えた後）は、キューを作って最初から再生する。
    /// - 同じプレイリストなら `play()` で一時停止した位置から再開する。
    ///
    /// 要実機検証：`ApplicationMusicPlayer` の再生がアプリをバックグラウンドに移した後や
    /// 画面ロック中も続くか。続かない場合は Background Modes の「Audio, AirPlay, and
    /// Picture in Picture」を有効にする（実際に音楽を流す用途なので審査上の問題はない。
    /// 禁止しているのは「無音を流し続けてアプリを生かす」手法）。
    func playForWork() async {
        guard canPlayMusic, let playlist = selectedPlaylist else { return }
        do {
            if queuedPlaylistID != playlist.id {
                player.queue = [playlist]   // Queue は配列リテラルで作れる（init(arrayLiteral:)）
                try await player.prepareToPlay()
                queuedPlaylistID = playlist.id
            }
            try await player.play()
        } catch {
            errorMessage = "再生できませんでした：\(error.localizedDescription)"
        }
    }

    /// 作業終了・一時停止・リセット時に呼ぶ。
    /// `stop()` ではなく `pause()` なので、次の作業開始時に続きから再開できる。
    func pauseForBreak() {
        guard player.state.playbackStatus == .playing else { return }
        player.pause()
    }
}
