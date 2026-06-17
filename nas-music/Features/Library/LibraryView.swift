//
//  LibraryView.swift
//  nas-music
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    init(musicRepository: MusicRepository) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(musicRepository: musicRepository))
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

            List {
                switch viewModel.selectedSegment {
                case .songs:
                    ForEach(Array(viewModel.filteredSongs.enumerated()), id: \.element.id) { index, song in
                        SongRowView(song: song)
                            .onTapGesture {
                                playbackManager.updatePlaylist(viewModel.filteredSongs, currentIndex: index)
                                playbackManager.play()
                            }
                    }
                case .albums:
                    ForEach(viewModel.filteredAlbums) { album in
                        NavigationLink(value: album) {
                            albumRow(album)
                        }
                    }
                case .artists:
                    ForEach(viewModel.filteredArtists) { artist in
                        artistRow(artist)
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索音乐")
        .navigationTitle("音乐库")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .task { await viewModel.load() }
    }

    private func albumRow(_ album: Album) -> some View {
        HStack(spacing: 12) {
            AlbumArtView(id: album.id, cornerRadius: 6)
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
    NavigationStack {
        LibraryView(musicRepository: MockMusicRepository())
    }
    .environmentObject(PlaybackManager())
}
