//
//  HomeView.swift
//  nas-music
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(musicRepository: MusicRepository) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(musicRepository: musicRepository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                searchField

                if viewModel.searchText.isEmpty {
                    recentlyPlayedSection
                    libraryStatsSection
                    recentlyAddedSection
                } else {
                    searchResultsSection
                }
            }
            .padding()
        }
        .navigationTitle("首页")
        .task { await viewModel.load() }
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

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "最近播放", actionTitle: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.recentlyPlayed.enumerated()), id: \.element.id) { index, song in
                        Button {
                            playbackManager.updatePlaylist(viewModel.recentlyPlayed, currentIndex: index)
                            playbackManager.play()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AlbumArtView(id: song.id.uuidString, cornerRadius: 10)
                                    .frame(width: 120, height: 120)
                                Text(song.album)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                    SongRowView(song: song)
                        .onTapGesture {
                            playbackManager.updatePlaylist(viewModel.recentlyAdded, currentIndex: index)
                            playbackManager.play()
                        }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { index, song in
                SongRowView(song: song)
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
    NavigationStack {
        HomeView(musicRepository: MockMusicRepository())
    }
    .environmentObject(PlaybackManager())
}
