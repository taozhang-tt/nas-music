//
//  LibraryView.swift
//  nas-music
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @ObservedObject private var syncService: MusicLibrarySyncService
    @ObservedObject private var metadataWritebackService: MetadataWritebackService
    @ObservedObject private var sessionManager: NASSessionManager
    @EnvironmentObject private var playbackManager: PlaybackManager
    private let providerStore: MusicLibraryProviderStore
    @State private var editingSong: Song?

    init(
        providerStore: MusicLibraryProviderStore,
        syncService: MusicLibrarySyncService,
        metadataWritebackService: MetadataWritebackService,
        sessionManager: NASSessionManager
    ) {
        self.providerStore = providerStore
        self.syncService = syncService
        self.metadataWritebackService = metadataWritebackService
        self.sessionManager = sessionManager
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
        .toolbar {
            NavigationLink {
                SearchView(providerStore: providerStore)
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album, provider: viewModel.activeProvider)
        }
        .sheet(item: $editingSong) { song in
            NavigationStack {
                NASMetadataEditorView(song: song, service: metadataWritebackService, sessionManager: sessionManager)
            }
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
            emptyLibraryView
        case .loaded:
            list
        }
    }

    private var emptyLibraryView: some View {
        ContentUnavailableView {
            Label("尚未同步音乐库", systemImage: "music.note.list")
        } description: {
            Text("同步后可以快速浏览和搜索 NAS 中的音乐。")
        } actions: {
            Button("立即同步") {
                Task { await viewModel.syncAndRefresh(using: syncService) }
            }
            .disabled(syncService.isSyncing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            syncStatusBanner

            switch viewModel.selectedSegment {
            case .songs:
                ForEach(Array(viewModel.filteredSongs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                        .onTapGesture {
                            playbackManager.updatePlaylist(viewModel.filteredSongs, currentIndex: index)
                            playbackManager.play()
                        }
                        .contextMenu {
                            Button {
                                editingSong = song
                            } label: {
                                Label("编辑 NAS 标签", systemImage: "tag")
                            }
                            .disabled(song.audioStationId == nil || metadataWritebackService.currentConfig?.isEnabled != true)
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
            case .playlists:
                ForEach(viewModel.filteredPlaylists) { playlist in
                    playlistRow(playlist)
                        .onAppear { viewModel.loadMorePlaylistsIfNeeded(currentItem: playlist) }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.syncAndRefresh(using: syncService) }
    }

    @ViewBuilder
    private var syncStatusBanner: some View {
        switch syncService.status {
        case .preparing:
            Label("准备同步音乐库", systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case .syncing(let current, let total, let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(total.map { "正在同步 \(current)/\($0) 首" } ?? "正在同步 \(current) 首")
                    Spacer()
                    Button("取消") { syncService.cancelSync() }
                }
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
            }
        case .rebuildingAlbums:
            Label("正在生成专辑索引", systemImage: "rectangle.stack")
                .foregroundStyle(.secondary)
        case .rebuildingArtists:
            Label("正在生成歌手索引", systemImage: "person.2")
                .foregroundStyle(.secondary)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Spacer()
                Button("重试") { Task { await viewModel.syncAndRefresh(using: syncService) } }
            }
        default:
            EmptyView()
        }
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

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.artworkGradient(for: playlist.id))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).font(.body)
                Text("\(playlist.songCount) 首歌曲").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let sessionManager = NASSessionManager()
    NavigationStack {
        LibraryView(
            providerStore: MusicLibraryProviderStore(sessionManager: sessionManager),
            syncService: MusicLibrarySyncService(sessionManager: sessionManager),
            metadataWritebackService: MetadataWritebackService(sessionManager: sessionManager),
            sessionManager: sessionManager
        )
    }
    .environmentObject(PlaybackManager())
}
