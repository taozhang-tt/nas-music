//
//  MiniPlayerView.swift
//  nas-music
//
//  固定在底部 TabView 上方的迷你播放器，跨所有 Tab 常驻显示。
//

import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var playbackManager: PlaybackManager
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
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    playbackManager.playPause()
                } label: {
                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button {
                    playbackManager.skipToNext()
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
