//
//  AudioStationMapper.swift
//  nas-music
//
//  把 Audio Station 返回的原始结构映射成 App 内统一的 Song / Album / Artist / Playlist。
//

import Foundation

enum AudioStationMapper {
    static func song(from raw: SynologySong) -> Song {
        Song(
            id: raw.id,
            title: raw.title,
            artist: raw.artist,
            album: raw.album,
            albumArtist: raw.albumArtist,
            duration: raw.duration,
            trackNumber: raw.trackNumber,
            discNumber: raw.discNumber,
            year: raw.year,
            genre: raw.genre,
            fileExtension: raw.fileExtension,
            bitrate: raw.bitrate,
            sampleRate: raw.sampleRate,
            fileSize: raw.fileSize,
            coverId: raw.coverId,
            path: raw.path,
            source: .synology(audioStationId: raw.id)
        )
    }

    static func album(from raw: SynologyAlbum) -> Album {
        let artistName = raw.artist ?? "未知歌手"
        // 用 ASCII Unit Separator 当分隔符——专辑名/歌手名几乎不可能包含这个控制字符，
        // 避免用 "::" 这种常见字符串组合时不同专辑撞出同一个 id。
        let id = "\(artistName)\u{1F}\(raw.name)"
        return Album(
            id: id,
            title: raw.name,
            artistName: artistName,
            trackCount: raw.songCount,
            coverId: raw.coverId,
            source: .synology(audioStationId: id)
        )
    }

    static func artist(from raw: SynologyArtist) -> Artist {
        Artist(id: raw.name, name: raw.name, songCount: raw.songCount ?? 0)
    }

    static func playlist(from raw: SynologyPlaylist) -> Playlist {
        Playlist(id: raw.id, name: raw.name, songCount: raw.songCount ?? 0)
    }
}
