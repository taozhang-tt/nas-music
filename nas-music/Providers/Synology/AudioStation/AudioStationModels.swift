//
//  AudioStationModels.swift
//  nas-music
//
//  Audio Station 歌曲/专辑/歌手/播放列表的响应模型。不同 DSM / Audio Station 版本字段
//  形态不完全一致（有的把 artist/album/duration 放在顶层，有的放在 additional.song_tag /
//  additional.song_audio 里；id/track/disc/year/bitrate 等数值有时是 JSON number，
//  有时是字符串），这里统一做宽松解析，缺失字段填 nil，不让单条数据格式异常拖垮整批解析。
//

import Foundation

/// 把 String/Int/Double 都当作字符串接受，应对不同版本里 id 字段类型不一致的情况。
struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            value = String(doubleValue)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "期望 String/Int/Double")
            )
        }
    }
}

struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
        } else if let stringValue = try? container.decode(String.self), let parsed = Double(stringValue) {
            value = parsed
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "期望 Double/Int/String")
            )
        }
    }
}

struct FlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue)
        } else if let stringValue = try? container.decode(String.self), let parsed = Int(stringValue) {
            value = parsed
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "期望 Int/Double/String")
            )
        }
    }
}

private func flexString<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> String? {
    (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
}

private func flexDouble<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    ((try? container.decodeIfPresent(FlexibleDouble.self, forKey: key)) ?? nil)?.value
}

private func flexInt<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    ((try? container.decodeIfPresent(FlexibleInt.self, forKey: key)) ?? nil)?.value
}

/// 让 SynologyAudioStationProvider 用一个通用的 fetchList(_:) helper 统一处理日志/错误码，
/// 不用给每种 list 响应各写一遍解码 + 判断 success 的代码。
protocol SynologyListResponse: Decodable {
    var success: Bool { get }
    var error: SynologyErrorPayload? { get }
}

// MARK: - SYNO.AudioStation.Song

struct SynologyAudioStationSongListResponse: SynologyListResponse {
    let success: Bool
    let data: SongListData?
    let error: SynologyErrorPayload?
}

struct SongListData: Decodable {
    let total: Int?
    let offset: Int?
    let songs: [SynologySong]?
}

struct SynologySong: Decodable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let fileExtension: String?
    let bitrate: Int?
    let sampleRate: Int?
    let fileSize: Int64?
    let coverId: String?
    let path: String?

    private enum RootKeys: String, CodingKey {
        case id, title, artist, album, path, cover, additional
        case albumArtist = "album_artist"
        case duration
        case size
    }
    private enum AdditionalKeys: String, CodingKey {
        case songTag = "song_tag"
        case songAudio = "song_audio"
    }
    private enum SongTagKeys: String, CodingKey {
        case album, artist, genre, track, disc, year
        case albumArtist = "album_artist"
    }
    private enum SongAudioKeys: String, CodingKey {
        case bitrate, duration
        case sampleRate = "samplerate"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)

        let rawPath = flexString(root, .path)
        path = rawPath
        id = flexString(root, .id) ?? rawPath ?? UUID().uuidString
        coverId = flexString(root, .cover)

        let rawTitle = flexString(root, .title)
        title = rawTitle ?? rawPath.map { ($0 as NSString).lastPathComponent } ?? "未知曲目"
        let pathExtension = rawPath.map { ($0 as NSString).pathExtension }
        fileExtension = (pathExtension?.isEmpty ?? true) ? nil : pathExtension

        var artistValue = flexString(root, .artist)
        var albumValue = flexString(root, .album)
        var albumArtistValue = flexString(root, .albumArtist)
        var durationValue = flexDouble(root, .duration)
        var genreValue: String?
        var trackValue: Int?
        var discValue: Int?
        var yearValue: Int?
        var bitrateValue: Int?
        var sampleRateValue: Int?

        if let additional = try? root.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .additional) {
            if let tag = try? additional.nestedContainer(keyedBy: SongTagKeys.self, forKey: .songTag) {
                albumValue = albumValue ?? flexString(tag, .album)
                artistValue = artistValue ?? flexString(tag, .artist)
                albumArtistValue = albumArtistValue ?? flexString(tag, .albumArtist)
                genreValue = flexString(tag, .genre)
                trackValue = flexInt(tag, .track)
                discValue = flexInt(tag, .disc)
                yearValue = flexInt(tag, .year)
            }
            if let audio = try? additional.nestedContainer(keyedBy: SongAudioKeys.self, forKey: .songAudio) {
                durationValue = durationValue ?? flexDouble(audio, .duration)
                bitrateValue = flexInt(audio, .bitrate)
                sampleRateValue = flexInt(audio, .sampleRate)
            }
        }

        artist = artistValue
        album = albumValue
        albumArtist = albumArtistValue
        duration = durationValue
        trackNumber = trackValue
        discNumber = discValue
        year = yearValue
        genre = genreValue
        bitrate = bitrateValue
        sampleRate = sampleRateValue
        fileSize = flexInt(root, .size).map { Int64($0) }
    }
}

// MARK: - SYNO.AudioStation.Album

struct SynologyAudioStationAlbumListResponse: SynologyListResponse {
    let success: Bool
    let data: AlbumListData?
    let error: SynologyErrorPayload?
}

struct AlbumListData: Decodable {
    let total: Int?
    let offset: Int?
    let albums: [SynologyAlbum]?
}

struct SynologyAlbum: Decodable {
    let name: String
    let artist: String?
    let songCount: Int?
    let coverId: String?

    private enum RootKeys: String, CodingKey {
        case name, artist, additional
    }
    private enum AdditionalKeys: String, CodingKey {
        case artist
        case songCount = "song_count"
        case coverId = "cover"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        name = flexString(root, .name) ?? "未知专辑"

        var artistValue = flexString(root, .artist)
        var songCountValue: Int?
        var coverValue: String?

        if let additional = try? root.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .additional) {
            artistValue = artistValue ?? flexString(additional, .artist)
            songCountValue = flexInt(additional, .songCount)
            coverValue = flexString(additional, .coverId)
        }

        artist = artistValue
        songCount = songCountValue
        coverId = coverValue
    }
}

// MARK: - SYNO.AudioStation.Artist

struct SynologyAudioStationArtistListResponse: SynologyListResponse {
    let success: Bool
    let data: ArtistListData?
    let error: SynologyErrorPayload?
}

struct ArtistListData: Decodable {
    let total: Int?
    let offset: Int?
    let artists: [SynologyArtist]?
}

struct SynologyArtist: Decodable {
    let name: String
    let songCount: Int?

    private enum RootKeys: String, CodingKey {
        case name, additional
    }
    private enum AdditionalKeys: String, CodingKey {
        case songCount = "song_count"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        name = flexString(root, .name) ?? "未知歌手"
        if let additional = try? root.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .additional) {
            songCount = flexInt(additional, .songCount)
        } else {
            songCount = nil
        }
    }
}

// MARK: - SYNO.AudioStation.Playlist

struct SynologyAudioStationPlaylistListResponse: SynologyListResponse {
    let success: Bool
    let data: PlaylistListData?
    let error: SynologyErrorPayload?
}

struct PlaylistListData: Decodable {
    let total: Int?
    let offset: Int?
    let playlists: [SynologyPlaylist]?
}

struct SynologyPlaylist: Decodable {
    let id: String
    let name: String
    let songCount: Int?

    private enum RootKeys: String, CodingKey {
        case id, name, additional
    }
    private enum AdditionalKeys: String, CodingKey {
        case songCount = "song_count"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        id = flexString(root, .id) ?? UUID().uuidString
        name = flexString(root, .name) ?? "未命名播放列表"
        if let additional = try? root.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .additional) {
            songCount = flexInt(additional, .songCount)
        } else {
            songCount = nil
        }
    }
}
