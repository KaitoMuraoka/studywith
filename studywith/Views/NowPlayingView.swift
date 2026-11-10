import MusicKit
import SwiftUI

/// 再生中の曲名とアートワーク。
///
/// `ApplicationMusicPlayer.Queue` と `MusicPlayer.State` は、Apple のドキュメント上
/// `Observable` に準拠しているため、body の中で読むだけで変化が反映されます。
/// （不確かな点：もし実機で曲が変わっても表示が更新されない場合は、
///   `@ObservedObject private var queue = ApplicationMusicPlayer.shared.queue` のように
///   `ObservableObject` として監視する書き方に切り替えてください。）
struct NowPlayingView: View {
    @Environment(MusicService.self) private var music

    private let player = ApplicationMusicPlayer.shared

    var body: some View {
        if music.canPlayMusic, let entry = player.queue.currentEntry {
            HStack(spacing: 12) {
                if let artwork = entry.artwork {
                    ArtworkImage(artwork, width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    placeholderArtwork
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: player.state.playbackStatus == .playing ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial, in: .rect(cornerRadius: 12))
        } else if music.canPlayMusic, let playlist = music.selectedPlaylist {
            // まだ再生していない（作業を開始していない）とき
            Label("「\(playlist.name)」を作業中に再生します", systemImage: "music.note")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 56, height: 56)
            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
    }
}
