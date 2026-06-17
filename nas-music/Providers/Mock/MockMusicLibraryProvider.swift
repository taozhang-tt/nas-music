//
//  MockMusicLibraryProvider.swift
//  nas-music
//
//  无 NAS 连接时使用的样例数据源：5 个专辑、31 首歌曲、8 位歌手、2 个播放列表。
//  fetchStreamURL 不发起任何网络请求——PlaybackManager 对 .mock 来源的歌曲走 Timer
//  模拟播放引擎，这里返回的 URL 只是一个不会被真正加载的占位符。
//

import Foundation

enum MockMusicLibraryProviderError: Error {
    case unsupportedSource
}

final class MockMusicLibraryProvider: MusicLibraryProvider {
    let albums: [Album]
    let artists: [Artist]
    let songs: [Song]
    let playlists: [Playlist]

    init() {
        func makeSongs(albumId: String, albumTitle: String, artistName: String, tracks: [(String, TimeInterval)]) -> [Song] {
            tracks.enumerated().map { index, track in
                let id = "\(albumId)-track-\(index)"
                return Song(
                    id: id,
                    title: track.0,
                    artist: artistName,
                    album: albumTitle,
                    albumArtist: artistName,
                    duration: track.1,
                    trackNumber: index + 1,
                    source: .mock(url: "mock://song/\(id)")
                )
            }
        }

        let novembersChopinSongs = makeSongs(
            albumId: "album-novembers-chopin", albumTitle: "十一月的肖邦", artistName: "周杰伦",
            tracks: [("夜曲", 228), ("枫", 271), ("黑色毛衣", 264), ("麦芽糖", 244), ("阳明山", 213)]
        )
        let nineteenEightyNineSongs = makeSongs(
            albumId: "album-1989-tv", albumTitle: "1989 (Taylor's Version)", artistName: "Taylor Swift",
            tracks: [
                ("Welcome To New York (Taylor's Version)", 212), ("Blank Space (Taylor's Version)", 231),
                ("Style (Taylor's Version)", 231), ("Shake It Off (Taylor's Version)", 219),
                ("Bad Blood (Taylor's Version)", 211), ("Wildest Dreams (Taylor's Version)", 220),
            ]
        )
        let darkSideOfTheMoonSongs = makeSongs(
            albumId: "album-dark-side-of-the-moon", albumTitle: "The Dark Side of the Moon", artistName: "Pink Floyd",
            tracks: [
                ("Speak to Me", 65), ("Breathe (In the Air)", 169), ("On the Run", 225), ("Time", 413),
                ("The Great Gig in the Sky", 284), ("Money", 382), ("Us and Them", 469),
                ("Any Colour You Like", 205), ("Brain Damage", 226), ("Eclipse", 123),
            ]
        )
        let rushOfBloodSongs = makeSongs(
            albumId: "album-rush-of-blood", albumTitle: "A Rush of Blood to the Head", artistName: "Coldplay",
            tracks: [("Politik", 310), ("The Scientist", 309), ("Clocks", 307), ("Daylight", 304), ("Amsterdam", 316)]
        )
        let harrysHouseSongs = makeSongs(
            albumId: "album-harrys-house", albumTitle: "Harry's House", artistName: "Harry Styles",
            tracks: [
                ("Music for a Sushi Restaurant", 193), ("Late Night Talking", 177), ("Grapejuice", 188),
                ("As It Was", 167), ("Daylight", 186),
            ]
        )

        albums = [
            Album(id: "album-novembers-chopin", title: "十一月的肖邦", artistName: "周杰伦", year: 2005, trackCount: novembersChopinSongs.count),
            Album(id: "album-1989-tv", title: "1989 (Taylor's Version)", artistName: "Taylor Swift", year: 2023, trackCount: nineteenEightyNineSongs.count),
            Album(id: "album-dark-side-of-the-moon", title: "The Dark Side of the Moon", artistName: "Pink Floyd", year: 1973, trackCount: darkSideOfTheMoonSongs.count),
            Album(id: "album-rush-of-blood", title: "A Rush of Blood to the Head", artistName: "Coldplay", year: 2002, trackCount: rushOfBloodSongs.count),
            Album(id: "album-harrys-house", title: "Harry's House", artistName: "Harry Styles", year: 2022, trackCount: harrysHouseSongs.count),
        ]

        songs = novembersChopinSongs + nineteenEightyNineSongs + darkSideOfTheMoonSongs + rushOfBloodSongs + harrysHouseSongs

        artists = [
            Artist(id: "artist-jay-chou", name: "周杰伦", songCount: 45),
            Artist(id: "artist-taylor-swift", name: "Taylor Swift", songCount: 12),
            Artist(id: "artist-jj-lin", name: "林俊杰", songCount: 8),
            Artist(id: "artist-coldplay", name: "Coldplay", songCount: rushOfBloodSongs.count),
            Artist(id: "artist-adele", name: "Adele", songCount: 6),
            Artist(id: "artist-ed-sheeran", name: "Ed Sheeran", songCount: 9),
            Artist(id: "artist-pink-floyd", name: "Pink Floyd", songCount: darkSideOfTheMoonSongs.count),
            Artist(id: "artist-harry-styles", name: "Harry Styles", songCount: harrysHouseSongs.count),
        ]

        playlists = [
            Playlist(id: "playlist-focus", name: "专注工作", songCount: 12),
            Playlist(id: "playlist-roadtrip", name: "公路旅行", songCount: 18),
        ]
    }

    func fetchSongs(offset: Int, limit: Int) async throws -> [Song] {
        page(of: songs, offset: offset, limit: limit)
    }

    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album] {
        page(of: albums, offset: offset, limit: limit)
    }

    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist] {
        page(of: artists, offset: offset, limit: limit)
    }

    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist] {
        page(of: playlists, offset: offset, limit: limit)
    }

    func fetchStreamURL(for song: Song) async throws -> URL {
        guard case .mock(let url) = song.source, let resolved = URL(string: url) else {
            throw MockMusicLibraryProviderError.unsupportedSource
        }
        return resolved
    }

    private func page<T>(of items: [T], offset: Int, limit: Int) -> [T] {
        guard offset < items.count, offset >= 0, limit > 0 else { return [] }
        let end = min(offset + limit, items.count)
        return Array(items[offset..<end])
    }
}
