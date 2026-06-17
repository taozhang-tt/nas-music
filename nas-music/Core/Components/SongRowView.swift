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
            AlbumArtView(id: song.id, cornerRadius: 6)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.duration.formattedAsMinutesSeconds)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
