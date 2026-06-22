//
//  SearchView.swift
//  nas-music
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    private let providerStore: MusicLibraryProviderStore
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(providerStore: MusicLibraryProviderStore) {
        self.providerStore = providerStore
        _viewModel = StateObject(wrappedValue: SearchViewModel(providerStore: providerStore))
    }

    var body: some View {
        content
            .navigationTitle("搜索")
            .searchable(text: $viewModel.keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索歌曲、专辑、歌手")
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album, provider: providerStore.activeProvider)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView("搜索音乐库", systemImage: "magnifyingglass", description: Text("输入歌曲、专辑或歌手名称。"))
        case .searching:
            ProgressView("搜索中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass", description: Text("换个关键词再试。"))
        case .failed(let message):
            ContentUnavailableView("搜索失败", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded(let result):
            resultList(result)
        }
    }

    private func resultList(_ result: MusicSearchResult) -> some View {
        List {
            if !result.songs.isEmpty {
                Section(SearchResultSection.songs.rawValue) {
                    ForEach(Array(result.songs.enumerated()), id: \.element.id) { index, song in
                        SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                            .onTapGesture {
                                playbackManager.updatePlaylist(result.songs, currentIndex: index)
                                playbackManager.play()
                            }
                    }
                }
            }

            if !result.albums.isEmpty {
                Section(SearchResultSection.albums.rawValue) {
                    ForEach(result.albums) { album in
                        NavigationLink(value: album) {
                            albumRow(album)
                        }
                    }
                }
            }

            if !result.artists.isEmpty {
                Section(SearchResultSection.artists.rawValue) {
                    ForEach(result.artists) { artist in
                        artistRow(artist)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func albumRow(_ album: Album) -> some View {
        HStack(spacing: 12) {
            ArtworkView(coverId: album.coverId, size: .medium, cornerRadius: 6, placeholderSeed: album.id)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(.body)
                Text(album.artistName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func artistRow(_ artist: Artist) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppTheme.artworkGradient(for: artist.id))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name).font(.body)
                Text("\(artist.songCount) 首歌曲").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
