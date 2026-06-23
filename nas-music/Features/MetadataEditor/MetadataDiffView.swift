//
//  MetadataDiffView.swift
//  nas-music
//

import SwiftUI

struct MetadataDiffView: View {
    let before: RemoteAudioMetadata
    let after: RemoteAudioMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasChanges {
                Text("没有检测到标签变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            diffRow("标题", before.title, after.title)
            diffRow("歌手", before.artist, after.artist)
            diffRow("专辑", before.album, after.album)
            diffRow("专辑歌手", before.albumArtist, after.albumArtist)
            diffRow("流派", before.genre, after.genre)
            diffRow("年份", before.year.map(String.init), after.year.map(String.init))
            diffRow("曲目编号", before.trackNumber.map(String.init), after.trackNumber.map(String.init))
            diffRow("碟片编号", before.discNumber.map(String.init), after.discNumber.map(String.init))
        }
    }

    private var hasChanges: Bool {
        before.title != after.title ||
        before.artist != after.artist ||
        before.album != after.album ||
        before.albumArtist != after.albumArtist ||
        before.genre != after.genre ||
        before.year != after.year ||
        before.trackNumber != after.trackNumber ||
        before.discNumber != after.discNumber
    }

    private func diffRow(_ label: String, _ beforeValue: String?, _ afterValue: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(beforeValue ?? "空") → \(afterValue ?? "空")")
                .font(.body)
                .foregroundStyle(beforeValue == afterValue ? .secondary : .primary)
        }
    }
}
