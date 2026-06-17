//
//  SongListView.swift
//  nas-music
//
//  通用的歌曲列表页：点击任意一行用整份列表替换播放队列。首页「全部歌曲」入口、
//  搜索结果等场景共用。
//

import SwiftUI

struct SongListView: View {
    let title: String
    let songs: [Song]
    @EnvironmentObject private var playbackManager: PlaybackManager

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView("没有找到歌曲", systemImage: "music.note")
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(song: song, isPlaying: playbackManager.currentSong?.id == song.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playbackManager.updatePlaylist(songs, currentIndex: index)
                            playbackManager.play()
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
