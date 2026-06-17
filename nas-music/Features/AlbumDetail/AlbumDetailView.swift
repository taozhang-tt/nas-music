//
//  AlbumDetailView.swift
//  nas-music
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(album: album))
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
                        Text("\(viewModel.album.year) · \(viewModel.album.trackCount) 首歌曲 · \(viewModel.formattedDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        playbackManager.updatePlaylist(viewModel.album.songs, currentIndex: 0)
                        playbackManager.play()
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(Array(viewModel.album.songs.enumerated()), id: \.element.id) { index, song in
                    HStack {
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        Text(song.title)
                        Spacer()
                        Text(song.duration.formattedAsMinutesSeconds)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playbackManager.updatePlaylist(viewModel.album.songs, currentIndex: index)
                        playbackManager.play()
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(viewModel.album.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: MockMusicRepository().albums[0])
    }
    .environmentObject(PlaybackManager())
}
