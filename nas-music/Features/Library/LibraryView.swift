//
//  LibraryView.swift
//  nas-music
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(providerStore: MusicLibraryProviderStore) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(providerStore: providerStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.selectedSegment) {
                ForEach(LibrarySegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索音乐")
        .navigationTitle("音乐库")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album, provider: viewModel.activeProvider)
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            errorView(message: message)
        case .empty:
            ContentUnavailableView("音乐库是空的", systemImage: "music.note.list", description: Text("请确认 NAS 已完成音乐索引"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            list
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重新加载") { Task { await viewModel.refresh() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            switch viewModel.selectedSegment {
            case .songs:
                ForEach(Array(viewModel.filteredSongs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                        .onTapGesture {
                            playbackManager.updatePlaylist(viewModel.filteredSongs, currentIndex: index)
                            playbackManager.play()
                        }
                        .onAppear { viewModel.loadMoreSongsIfNeeded(currentItem: song) }
                }
            case .albums:
                ForEach(viewModel.filteredAlbums) { album in
                    NavigationLink(value: album) {
                        albumRow(album)
                    }
                    .onAppear { viewModel.loadMoreAlbumsIfNeeded(currentItem: album) }
                }
            case .artists:
                ForEach(viewModel.filteredArtists) { artist in
                    artistRow(artist)
                        .onAppear { viewModel.loadMoreArtistsIfNeeded(currentItem: artist) }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
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

#Preview {
    let sessionManager = NASSessionManager()
    NavigationStack {
        LibraryView(providerStore: MusicLibraryProviderStore(sessionManager: sessionManager))
    }
    .environmentObject(PlaybackManager())
}
