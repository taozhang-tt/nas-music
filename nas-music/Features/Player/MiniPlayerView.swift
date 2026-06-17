//
//  MiniPlayerView.swift
//  nas-music
//
//  固定在底部 TabView 上方的迷你播放器，跨所有 Tab 常驻显示。
//  PlaybackManager 从 @EnvironmentObject 拿，和其它页面共享同一份播放状态。
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager
    let onTap: () -> Void

    var body: some View {
        if let song = playbackManager.currentSong {
            HStack(spacing: 12) {
                AlbumArtView(id: song.id, cornerRadius: 6)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(playbackManager.playbackError ?? (song.artist ?? "未知歌手"))
                        .font(.caption)
                        .foregroundStyle(playbackManager.playbackError == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    playbackManager.toggle()
                } label: {
                    if playbackManager.isLoadingStream {
                        ProgressView()
                    } else {
                        Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(playbackManager.isLoadingStream)

                Button {
                    playbackManager.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}

private func makePreviewPlaybackManager() -> PlaybackManager {
    let provider = MockMusicLibraryProvider()
    let manager = PlaybackManager(musicLibraryProvider: provider)
    manager.updatePlaylist(provider.songs, currentIndex: 0)
    manager.play()
    return manager
}

#Preview {
    VStack {
        Spacer()
        MiniPlayerView(onTap: {})
    }
    .environmentObject(makePreviewPlaybackManager())
}
