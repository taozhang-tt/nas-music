//
//  SongRepositoryTests.swift
//  nas-musicTests
//

import XCTest
@testable import nas_music

@MainActor
final class SongRepositoryTests: XCTestCase {
    private var database: DatabaseManager!
    private var repository: SongRepository!

    override func setUpWithError() throws {
        database = try DatabaseManager(path: makeDatabaseURL())
        repository = SongRepository(database: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    func testUpsertUpdatesExistingSongInsteadOfDuplicating() async throws {
        let first = makeSong(sourceId: "1", title: "First Title")
        let updated = makeSong(sourceId: "1", title: "Updated Title")

        try await repository.upsert(songs: [first], nasId: "nas-a", syncTime: Date())
        try await repository.upsert(songs: [updated], nasId: "nas-a", syncTime: Date())

        let songs = try await repository.fetchSongs(nasId: "nas-a", offset: 0, limit: 10)
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs.first?.title, "Updated Title")
    }

    func testDifferentNASLibrariesAreIsolated() async throws {
        try await repository.upsert(songs: [makeSong(sourceId: "1", title: "NAS A")], nasId: "nas-a", syncTime: Date())
        try await repository.upsert(songs: [makeSong(sourceId: "1", title: "NAS B")], nasId: "nas-b", syncTime: Date())

        let nasA = try await repository.fetchSongs(nasId: "nas-a", offset: 0, limit: 10)
        let nasB = try await repository.fetchSongs(nasId: "nas-b", offset: 0, limit: 10)

        XCTAssertEqual(nasA.map(\.title), ["NAS A"])
        XCTAssertEqual(nasB.map(\.title), ["NAS B"])
    }

    func testFetchSongsPaginatesInTitleOrder() async throws {
        let songs = [
            makeSong(sourceId: "3", title: "Charlie"),
            makeSong(sourceId: "1", title: "Alpha"),
            makeSong(sourceId: "2", title: "Bravo"),
        ]
        try await repository.upsert(songs: songs, nasId: "nas-a", syncTime: Date())

        let page = try await repository.fetchSongs(nasId: "nas-a", offset: 1, limit: 1)

        XCTAssertEqual(page.map(\.title), ["Bravo"])
    }

    func testSearchMatchesTitleArtistAndAlbum() async throws {
        let songs = [
            makeSong(sourceId: "1", title: "Nocturne", artist: "Jay Chou", album: "November"),
            makeSong(sourceId: "2", title: "Time", artist: "Pink Floyd", album: "The Dark Side"),
        ]
        try await repository.upsert(songs: songs, nasId: "nas-a", syncTime: Date())

        let artistMatches = try await repository.search(nasId: "nas-a", keyword: "jay", offset: 0, limit: 10)
        let albumMatches = try await repository.search(nasId: "nas-a", keyword: "dark", offset: 0, limit: 10)
        let titleMatches = try await repository.search(nasId: "nas-a", keyword: "TIME", offset: 0, limit: 10)

        XCTAssertEqual(artistMatches.map(\.title), ["Nocturne"])
        XCTAssertEqual(albumMatches.map(\.title), ["Time"])
        XCTAssertEqual(titleMatches.map(\.title), ["Time"])
    }

    func testMarkMissingAsDeletedOnlyHidesOldRecords() async throws {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        try await repository.upsert(songs: [makeSong(sourceId: "old", title: "Old")], nasId: "nas-a", syncTime: oldDate)
        try await repository.upsert(songs: [makeSong(sourceId: "new", title: "New")], nasId: "nas-a", syncTime: newDate)

        try await repository.markMissingAsDeleted(nasId: "nas-a", lastSeenBefore: newDate)

        let songs = try await repository.fetchSongs(nasId: "nas-a", offset: 0, limit: 10)
        XCTAssertEqual(songs.map(\.title), ["New"])
    }

    private func makeSong(
        sourceId: String,
        title: String,
        artist: String = "Artist",
        album: String = "Album"
    ) -> Song {
        Song(
            id: "synology-\(sourceId)",
            title: title,
            artist: artist,
            album: album,
            albumArtist: artist,
            duration: 180,
            trackNumber: 1,
            coverId: "cover-\(sourceId)",
            source: .synology(audioStationId: sourceId)
        )
    }

    private func makeDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nas-music-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite")
    }
}
