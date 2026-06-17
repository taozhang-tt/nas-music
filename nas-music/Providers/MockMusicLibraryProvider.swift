//
//  MockMusicLibraryProvider.swift
//  nas-music
//
//  暂时使用的 Mock 数据源，覆盖首页/音乐库/专辑详情/播放器/队列所需的样例数据。
//

import Foundation

final class MockMusicLibraryProvider: MusicLibraryProviding {
    let albums: [Album]
    let standaloneSongs: [Song]
    let artists: [Artist]

    init() {
        let novembersChopin = Album(
            id: "album-novembers-chopin",
            title: "十一月的肖邦",
            artistName: "周杰伦",
            year: 2005,
            songs: [
                Song(id: "song-nocturne", title: "夜曲", artistName: "周杰伦", albumTitle: "十一月的肖邦", duration: 228, trackNumber: 1),
                Song(id: "song-maple", title: "枫", artistName: "周杰伦", albumTitle: "十一月的肖邦", duration: 271, trackNumber: 2),
                Song(id: "song-black-sweater", title: "黑色毛衣", artistName: "周杰伦", albumTitle: "十一月的肖邦", duration: 264, trackNumber: 3),
                Song(id: "song-malt-candy", title: "麦芽糖", artistName: "周杰伦", albumTitle: "十一月的肖邦", duration: 244, trackNumber: 4),
                Song(id: "song-yangmingshan", title: "阳明山", artistName: "周杰伦", albumTitle: "十一月的肖邦", duration: 213, trackNumber: 5),
            ]
        )

        let nineteenEightyNine = Album(
            id: "album-1989-tv",
            title: "1989 (Taylor's Version)",
            artistName: "Taylor Swift",
            year: 2023,
            songs: [
                Song(id: "song-welcome-to-ny", title: "Welcome To New York (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 212, trackNumber: 1),
                Song(id: "song-blank-space", title: "Blank Space (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 231, trackNumber: 2),
                Song(id: "song-style", title: "Style (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 231, trackNumber: 3),
                Song(id: "song-shake-it-off", title: "Shake It Off (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 219, trackNumber: 4),
                Song(id: "song-bad-blood", title: "Bad Blood (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 211, trackNumber: 5),
                Song(id: "song-wildest-dreams", title: "Wildest Dreams (Taylor's Version)", artistName: "Taylor Swift", albumTitle: "1989 (Taylor's Version)", duration: 220, trackNumber: 6),
            ]
        )

        let darkSideOfTheMoon = Album(
            id: "album-dark-side-of-the-moon",
            title: "The Dark Side of the Moon",
            artistName: "Pink Floyd",
            year: 1973,
            songs: [
                Song(id: "song-speak-to-me", title: "Speak to Me", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 65, trackNumber: 1),
                Song(id: "song-breathe", title: "Breathe (In the Air)", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 169, trackNumber: 2),
                Song(id: "song-on-the-run", title: "On the Run", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 225, trackNumber: 3),
                Song(id: "song-time", title: "Time", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 413, trackNumber: 4),
                Song(id: "song-great-gig", title: "The Great Gig in the Sky", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 284, trackNumber: 5),
                Song(id: "song-money", title: "Money", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 382, trackNumber: 6),
                Song(id: "song-us-and-them", title: "Us and Them", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 469, trackNumber: 7),
                Song(id: "song-any-colour", title: "Any Colour You Like", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 205, trackNumber: 8),
                Song(id: "song-brain-damage", title: "Brain Damage", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 226, trackNumber: 9),
                Song(id: "song-eclipse", title: "Eclipse", artistName: "Pink Floyd", albumTitle: "The Dark Side of the Moon", duration: 123, trackNumber: 10),
            ]
        )

        self.albums = [novembersChopin, nineteenEightyNine, darkSideOfTheMoon]

        self.standaloneSongs = [
            Song(id: "song-as-it-was", title: "As It Was", artistName: "Harry Styles", albumTitle: "Harry's House", duration: 167, trackNumber: 1),
            Song(id: "song-the-scientist", title: "The Scientist", artistName: "Coldplay", albumTitle: "A Rush of Blood to the Head", duration: 309, trackNumber: 1),
            Song(id: "song-another-love", title: "Another Love", artistName: "Tom Odell", albumTitle: "Long Way Down", duration: 244, trackNumber: 1),
        ]

        self.artists = [
            Artist(id: "artist-jay-chou", name: "周杰伦", songCount: 45),
            Artist(id: "artist-taylor-swift", name: "Taylor Swift", songCount: 12),
            Artist(id: "artist-jj-lin", name: "林俊杰", songCount: 8),
            Artist(id: "artist-coldplay", name: "Coldplay", songCount: 10),
            Artist(id: "artist-adele", name: "Adele", songCount: 6),
            Artist(id: "artist-ed-sheeran", name: "Ed Sheeran", songCount: 9),
            Artist(id: "artist-pink-floyd", name: "Pink Floyd", songCount: darkSideOfTheMoon.trackCount),
        ]
    }

    func fetchRecentlyPlayed() async -> [Song] {
        [albums[0].songs[0], albums[1].songs[0], albums[2].songs[3]]
    }

    func fetchRecentlyAdded() async -> [Song] {
        standaloneSongs
    }

    func fetchAllSongs() async -> [Song] {
        albums.flatMap(\.songs) + standaloneSongs
    }

    func fetchAllAlbums() async -> [Album] {
        albums
    }

    func fetchAllArtists() async -> [Artist] {
        artists
    }
}
