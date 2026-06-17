//
//  HomeView.swift
//  nas-music
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager
    let onNavigateToSettings: () -> Void

    init(providerStore: MusicLibraryProviderStore, onNavigateToSettings: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(providerStore: providerStore))
        self.onNavigateToSettings = onNavigateToSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                searchField
                nasStatusCard

                if viewModel.searchText.isEmpty {
                    content
                } else {
                    searchResultsSection
                }
            }
            .padding()
        }
        .navigationTitle("首页")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载中…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let message):
            errorSection(message: message)
        case .empty:
            Text("音乐库是空的")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .loaded:
            Group {
                libraryStatsSection
                recentlyAddedSection
                allSongsEntrySection
                if !viewModel.playlists.isEmpty {
                    playlistsSection
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索音乐", text: $viewModel.searchText)
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.updateSearchResults()
                }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var nasStatusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(nasStatusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(nasStatusTitle).font(.body.weight(.medium))
                if let detail = nasStatusDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsSettingsShortcut {
                Button(nasShortcutTitle) { onNavigateToSettings() }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var nasStatusColor: Color {
        switch viewModel.nasConnectionState {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        case .failed: .red
        }
    }

    private var nasStatusTitle: String {
        switch viewModel.nasConnectionState {
        case .connected: "已连接 NAS"
        case .connecting: "正在连接 NAS…"
        case .disconnected: "未连接 NAS"
        case .failed: "NAS 连接失败"
        }
    }

    private var nasStatusDetail: String? {
        switch viewModel.nasConnectionState {
        case .connected:
            var parts: [String] = []
            if let name = viewModel.nasDisplayName { parts.append(name) }
            if let lastConnectedAt = viewModel.nasLastConnectedAt {
                parts.append("最近同步 \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .failed(let message):
            return message
        case .disconnected:
            return "当前显示的是示例音乐库，去设置页连接 NAS 播放真实音乐"
        case .connecting:
            return nil
        }
    }

    private var showsSettingsShortcut: Bool {
        switch viewModel.nasConnectionState {
        case .disconnected, .failed: true
        case .connected, .connecting: false
        }
    }

    private var nasShortcutTitle: String {
        if case .failed = viewModel.nasConnectionState { return "重新连接" }
        return "去连接"
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新加载") { Task { await viewModel.refresh() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var libraryStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "我的收藏", actionTitle: nil)

            HStack(spacing: 12) {
                statCard(title: "歌曲", value: viewModel.songCount, icon: "music.note")
                statCard(title: "专辑", value: viewModel.albumCount, icon: "square.stack")
                statCard(title: "歌手", value: viewModel.artistCount, icon: "person.2")
            }
        }
    }

    private func statCard(title: String, value: Int, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("\(value)")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "最近添加", actionTitle: nil)

            VStack(spacing: 14) {
                ForEach(Array(viewModel.recentlyAdded.enumerated()), id: \.element.id) { index, song in
                    SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                        .onTapGesture {
                            playbackManager.updatePlaylist(viewModel.recentlyAdded, currentIndex: index)
                            playbackManager.play()
                        }
                }
            }
        }
    }

    private var allSongsEntrySection: some View {
        NavigationLink {
            SongListView(title: "全部歌曲", songs: viewModel.allSongsPreview)
        } label: {
            HStack {
                Label("全部歌曲", systemImage: "music.note.list")
                Spacer()
                Text("\(viewModel.songCount) 首")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "播放列表", actionTitle: nil)

            VStack(spacing: 10) {
                ForEach(viewModel.playlists) { playlist in
                    HStack {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(Color.accentColor)
                        Text(playlist.name)
                        Spacer()
                        Text("\(playlist.songCount) 首")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, song in
                SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                    .onTapGesture {
                        playbackManager.updatePlaylist(viewModel.searchResults, currentIndex: index)
                        playbackManager.play()
                    }
            }

            if viewModel.searchResults.isEmpty {
                Text("没有找到相关歌曲")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

#Preview {
    let sessionManager = NASSessionManager()
    NavigationStack {
        HomeView(providerStore: MusicLibraryProviderStore(sessionManager: sessionManager), onNavigateToSettings: {})
    }
    .environmentObject(PlaybackManager())
}
