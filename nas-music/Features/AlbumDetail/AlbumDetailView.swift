//
//  AlbumDetailView.swift
//  nas-music
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel

    init(album: Album, playbackManager: PlaybackManager) {
        _viewModel = StateObject(
            wrappedValue: AlbumDetailViewModel(album: album, playbackManager: playbackManager)
        )
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
                        viewModel.playAll()
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
                        Text("\(song.trackNumber)")
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
                    .onTapGesture { viewModel.playSong(at: index) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(viewModel.album.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
