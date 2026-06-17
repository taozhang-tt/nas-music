//
//  PlaybackManagerTests.swift
//  nas-musicTests
//

import XCTest
@testable import nas_music

@MainActor
final class PlaybackManagerTests: XCTestCase {

    private func makeSongs(count: Int, duration: TimeInterval = 200) -> [Song] {
        (0..<count).map { index in
            Song(
                id: UUID(),
                title: "Song \(index)",
                artist: "Artist \(index)",
                album: "Album",
                duration: duration,
                coverURL: nil,
                streamURL: nil
            )
        }
    }

    func testUpdatePlaylistSetsCurrentSongWithoutPlaying() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)

        manager.updatePlaylist(songs, currentIndex: 1)

        XCTAssertEqual(manager.currentSong?.id, songs[1].id)
        XCTAssertEqual(manager.currentTime, 0)
        XCTAssertFalse(manager.isPlaying)
    }

    func testNextAdvancesSequentially() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)
        manager.updatePlaylist(songs, currentIndex: 0)

        manager.next()
        XCTAssertEqual(manager.currentSong?.id, songs[1].id)

        manager.next()
        XCTAssertEqual(manager.currentSong?.id, songs[2].id)
    }

    func testNextWrapsAroundAtEndOfPlaylist() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)
        manager.updatePlaylist(songs, currentIndex: 2)

        manager.next()

        XCTAssertEqual(manager.currentSong?.id, songs[0].id)
    }

    func testPreviousMovesBackSequentially() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)
        manager.updatePlaylist(songs, currentIndex: 2)

        manager.previous()

        XCTAssertEqual(manager.currentSong?.id, songs[1].id)
    }

    func testPreviousWrapsAroundAtStartOfPlaylist() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)
        manager.updatePlaylist(songs, currentIndex: 0)

        manager.previous()

        XCTAssertEqual(manager.currentSong?.id, songs[2].id)
    }

    func testSeekClampsWithinValidRange() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 1, duration: 100)
        manager.updatePlaylist(songs, currentIndex: 0)

        manager.seek(to: 50)
        XCTAssertEqual(manager.currentTime, 50)

        manager.seek(to: 999)
        XCTAssertEqual(manager.currentTime, 100)

        manager.seek(to: -10)
        XCTAssertEqual(manager.currentTime, 0)
    }

    func testAutoAdvancesToNextSongWhenCurrentTimeReachesDuration() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 2, duration: 3)
        manager.updatePlaylist(songs, currentIndex: 0)
        manager.play()

        manager.tick()
        manager.tick()
        XCTAssertEqual(manager.currentSong?.id, songs[0].id)

        manager.tick()

        XCTAssertEqual(manager.currentSong?.id, songs[1].id)
        XCTAssertEqual(manager.currentTime, 0)
    }

    func testRepeatOneReplaysSameSongInsteadOfAdvancing() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 2, duration: 3)
        manager.updatePlaylist(songs, currentIndex: 0)
        manager.repeatMode = .one
        manager.play()

        manager.tick()
        manager.tick()
        manager.tick()

        XCTAssertEqual(manager.currentSong?.id, songs[0].id)
        XCTAssertEqual(manager.currentTime, 0)
    }

    func testPlaySongJumpsToExistingSongWithoutChangingPlaylist() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 3)
        manager.updatePlaylist(songs, currentIndex: 0)
        manager.play()

        manager.play(song: songs[2])

        XCTAssertEqual(manager.currentSong?.id, songs[2].id)
        XCTAssertEqual(manager.playlist.count, 3)
        XCTAssertTrue(manager.isPlaying)
    }

    func testToggleSwitchesBetweenPlayAndPause() {
        let manager = PlaybackManager()
        let songs = makeSongs(count: 1)
        manager.updatePlaylist(songs, currentIndex: 0)

        XCTAssertFalse(manager.isPlaying)

        manager.toggle()
        XCTAssertTrue(manager.isPlaying)

        manager.toggle()
        XCTAssertFalse(manager.isPlaying)
    }
}
