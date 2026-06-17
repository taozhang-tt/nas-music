//
//  AlbumDetailView.swift
//  nas-music
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(album: Album, provider: MusicLibraryProvider) {
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album, provider: provider))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AlbumArtView(id: viewModel.album.id, cornerRadius: 12)
                        .frame(width: 200, height: 200)

                    VStack(spacing: 4) {
                        Text(viewModel.album.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(viewModel.album.artistName)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if !viewModel.subtitle.isEmpty {
                            Text(viewModel.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        playbackManager.updatePlaylist(viewModel.songs, currentIndex: 0)
                        playbackManager.play()
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.songs.isEmpty)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
            }

            switch viewModel.state {
            case .idle, .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView("加载中…")
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            case .failed(let message):
                Section {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重新加载") { Task { await viewModel.refresh() } }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                }
            case .empty:
                Section {
                    Text("这张专辑还没有找到曲目。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            case .loaded:
                Section {
                    ForEach(Array(viewModel.songs.enumerated()), id: \.element.id) { index, song in
                        HStack {
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(song.title)
                            Spacer()
                            Text((song.duration ?? 0).formattedAsMinutesSeconds)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playbackManager.updatePlaylist(viewModel.songs, currentIndex: index)
                            playbackManager.play()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(viewModel.album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

#Preview {
    let mockProvider = MockMusicLibraryProvider()
    NavigationStack {
        AlbumDetailView(album: mockProvider.albums[0], provider: mockProvider)
    }
    .environmentObject(PlaybackManager())
}
