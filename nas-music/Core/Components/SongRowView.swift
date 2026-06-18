//
//  SongRowView.swift
//  nas-music
//
//  Home / Library / AlbumDetail / 搜索结果共用的歌曲行。
//

import SwiftUI

struct SongRowView: View {
    let song: Song
    var isPlaying: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(coverId: song.coverId, size: .thumbnail, cornerRadius: 6, placeholderSeed: song.id)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text(song.artist ?? "未知歌手")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text((song.duration ?? 0).formattedAsMinutesSeconds)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
