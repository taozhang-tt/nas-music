//
//  QueueView.swift
//  nas-music
//
//  播放队列：展示当前播放列表，点击任意歌曲切换播放。
//  直接绑定 @EnvironmentObject 的 PlaybackManager。
//

import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if playbackManager.playlist.indices.contains(playbackManager.currentIndex) {
                    Section("正在播放") {
                        row(for: playbackManager.playlist[playbackManager.currentIndex], at: playbackManager.currentIndex)
                    }
                }

                let upcoming = playbackManager.playlist.indices.filter { $0 > playbackManager.currentIndex }
                if !upcoming.isEmpty {
                    Section("接下来播放") {
                        ForEach(upcoming, id: \.self) { index in
                            row(for: playbackManager.playlist[index], at: index)
                        }
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(for song: Song, at index: Int) -> some View {
        SongRowView(song: song, isPlaying: index == playbackManager.currentIndex)
            .contentShape(Rectangle())
            .onTapGesture { playbackManager.play(song: song) }
    }
}

private func makePreviewPlaybackManager() -> PlaybackManager {
    let manager = PlaybackManager()
    let repository = MockMusicRepository()
    manager.updatePlaylist(repository.songs, currentIndex: 0)
    manager.play()
    return manager
}

#Preview {
    QueueView()
        .environmentObject(makePreviewPlaybackManager())
}
