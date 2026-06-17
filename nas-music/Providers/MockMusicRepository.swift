//
//  MockMusicRepository.swift
//  nas-music
//
//  暂时使用的 Mock 数据源：5 个专辑、31 首歌曲、8 位歌手，
//  覆盖首页/音乐库/专辑详情/播放器/队列所需的样例数据。
//

import Foundation

final class MockMusicRepository: MusicRepository {
    let albums: [Album]
    let artists: [Artist]
    let songs: [Song]

    private let recentlyPlayedSongs: [Song]
    private let recentlyAddedSongs: [Song]

    init() {
        let novembersChopin = Album(
            id: "album-novembers-chopin",
            title: "十一月的肖邦",
            artistName: "周杰伦",
            year: 2005,
            songs: [
                Song(id: UUID(), title: "夜曲", artist: "周杰伦", album: "十一月的肖邦", duration: 228, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "枫", artist: "周杰伦", album: "十一月的肖邦", duration: 271, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "黑色毛衣", artist: "周杰伦", album: "十一月的肖邦", duration: 264, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "麦芽糖", artist: "周杰伦", album: "十一月的肖邦", duration: 244, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "阳明山", artist: "周杰伦", album: "十一月的肖邦", duration: 213, coverURL: nil, streamURL: nil),
            ]
        )

        let nineteenEightyNine = Album(
            id: "album-1989-tv",
            title: "1989 (Taylor's Version)",
            artistName: "Taylor Swift",
            year: 2023,
            songs: [
                Song(id: UUID(), title: "Welcome To New York (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 212, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Blank Space (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 231, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Style (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 231, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Shake It Off (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 219, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Bad Blood (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 211, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Wildest Dreams (Taylor's Version)", artist: "Taylor Swift", album: "1989 (Taylor's Version)", duration: 220, coverURL: nil, streamURL: nil),
            ]
        )

        let darkSideOfTheMoon = Album(
            id: "album-dark-side-of-the-moon",
            title: "The Dark Side of the Moon",
            artistName: "Pink Floyd",
            year: 1973,
            songs: [
                Song(id: UUID(), title: "Speak to Me", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 65, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Breathe (In the Air)", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 169, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "On the Run", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 225, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "The Great Gig in the Sky", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 284, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Money", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 382, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Us and Them", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 469, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Any Colour You Like", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 205, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Brain Damage", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 226, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Eclipse", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 123, coverURL: nil, streamURL: nil),
            ]
        )

        let rushOfBlood = Album(
            id: "album-rush-of-blood",
            title: "A Rush of Blood to the Head",
            artistName: "Coldplay",
            year: 2002,
            songs: [
                Song(id: UUID(), title: "Politik", artist: "Coldplay", album: "A Rush of Blood to the Head", duration: 310, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "The Scientist", artist: "Coldplay", album: "A Rush of Blood to the Head", duration: 309, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Clocks", artist: "Coldplay", album: "A Rush of Blood to the Head", duration: 307, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Daylight", artist: "Coldplay", album: "A Rush of Blood to the Head", duration: 304, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Amsterdam", artist: "Coldplay", album: "A Rush of Blood to the Head", duration: 316, coverURL: nil, streamURL: nil),
            ]
        )

        let harrysHouse = Album(
            id: "album-harrys-house",
            title: "Harry's House",
            artistName: "Harry Styles",
            year: 2022,
            songs: [
                Song(id: UUID(), title: "Music for a Sushi Restaurant", artist: "Harry Styles", album: "Harry's House", duration: 193, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Late Night Talking", artist: "Harry Styles", album: "Harry's House", duration: 177, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Grapejuice", artist: "Harry Styles", album: "Harry's House", duration: 188, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "As It Was", artist: "Harry Styles", album: "Harry's House", duration: 167, coverURL: nil, streamURL: nil),
                Song(id: UUID(), title: "Daylight", artist: "Harry Styles", album: "Harry's House", duration: 186, coverURL: nil, streamURL: nil),
            ]
        )

        let albums = [novembersChopin, nineteenEightyNine, darkSideOfTheMoon, rushOfBlood, harrysHouse]
        self.albums = albums
        self.songs = albums.flatMap(\.songs)

        self.recentlyPlayedSongs = [
            novembersChopin.songs[0],
            nineteenEightyNine.songs[3],
            darkSideOfTheMoon.songs[3],
            rushOfBlood.songs[1],
            harrysHouse.songs[3],
        ]

        self.recentlyAddedSongs = [
            harrysHouse.songs[3],
            rushOfBlood.songs[1],
            nineteenEightyNine.songs[0],
        ]

        self.artists = [
            Artist(id: "artist-jay-chou", name: "周杰伦", songCount: 45),
            Artist(id: "artist-taylor-swift", name: "Taylor Swift", songCount: 12),
            Artist(id: "artist-jj-lin", name: "林俊杰", songCount: 8),
            Artist(id: "artist-coldplay", name: "Coldplay", songCount: rushOfBlood.trackCount),
            Artist(id: "artist-adele", name: "Adele", songCount: 6),
            Artist(id: "artist-ed-sheeran", name: "Ed Sheeran", songCount: 9),
            Artist(id: "artist-pink-floyd", name: "Pink Floyd", songCount: darkSideOfTheMoon.trackCount),
            Artist(id: "artist-harry-styles", name: "Harry Styles", songCount: harrysHouse.trackCount),
        ]
    }

    func fetchRecentlyPlayed() async -> [Song] {
        recentlyPlayedSongs
    }

    func fetchRecentlyAdded() async -> [Song] {
        recentlyAddedSongs
    }

    func fetchAllSongs() async -> [Song] {
        songs
    }

    func fetchAllAlbums() async -> [Album] {
        albums
    }

    func fetchAllArtists() async -> [Artist] {
        artists
    }
}
