import MusicKit
import SwiftUI

/// プレイリスト選択画面：「ライブラリ」と「カタログ検索」をタブで切り替える。
struct PlaylistPickerView: View {
    enum Source: String, CaseIterable, Identifiable {
        case library = "ライブラリ"
        case catalog = "カタログ検索"
        var id: Self { self }
    }

    @Environment(PomodoroController.self) private var controller
    @Environment(MusicService.self) private var music
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .library

    var body: some View {
        NavigationStack {
            Group {
                if music.canPlayMusic {
                    switch source {
                    case .library: LibraryPlaylistList(onSelect: select)
                    case .catalog: CatalogSearchList(onSelect: select)
                    }
                } else {
                    ContentUnavailableView(
                        "Apple Music を利用できません",
                        systemImage: "music.note",
                        description: Text("メイン画面の案内を確認してください。")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("取得元", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("プレイリスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func select(_ playlist: Playlist) {
        // PomodoroController 経由で選ぶ（作業中ならすぐ切り替えるため）
        controller.select(playlist)
        dismiss()
    }
}

// MARK: - ライブラリ

private struct LibraryPlaylistList: View {
    @Environment(MusicService.self) private var music
    @State private var playlists: MusicItemCollection<Playlist> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let onSelect: @MainActor (Playlist) -> Void

    var body: some View {
        List(playlists) { playlist in
            PlaylistRow(playlist: playlist, isSelected: playlist.id == music.selectedPlaylist?.id)
                .contentShape(.rect)
                .onTapGesture { onSelect(playlist) }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("読み込めませんでした", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if playlists.isEmpty {
                ContentUnavailableView("プレイリストがありません", systemImage: "music.note.list", description: Text("ミュージックアプリでプレイリストを作るか、カタログ検索を使ってください。"))
            }
        }
        .task {
            do {
                playlists = try await music.fetchLibraryPlaylists()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - カタログ検索

private struct CatalogSearchList: View {
    @Environment(MusicService.self) private var music
    @State private var searchText = ""
    @State private var playlists: MusicItemCollection<Playlist> = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    /// すぐ試せる検索ワード
    private let suggestions = ["集中", "Lo-fi", "勉強", "クラシック"]

    let onSelect: @MainActor (Playlist) -> Void

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { word in
                            Button(word) {
                                searchText = word
                                Task { await search() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section {
                ForEach(playlists) { playlist in
                    PlaylistRow(playlist: playlist, isSelected: playlist.id == music.selectedPlaylist?.id)
                        .contentShape(.rect)
                        .onTapGesture { onSelect(playlist) }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "プレイリストを検索")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView("検索できませんでした", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
    }

    private func search() async {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            playlists = try await music.searchCatalogPlaylists(term: term)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

// MARK: - 行

private struct PlaylistRow: View {
    let playlist: Playlist
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading) {
                Text(playlist.name)
                    .lineLimit(1)
                if let curator = playlist.curatorName {
                    Text(curator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}
