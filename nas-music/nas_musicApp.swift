//
//  nas_musicApp.swift
//  nas-music
//
//  Created by wuchang on 2026/6/17.
//
//  组合根：创建 Mock Provider 并注入到 RootTabView。
//

import SwiftUI

@main
struct nas_musicApp: App {
    private let musicLibrary: MusicLibraryProviding
    @StateObject private var playbackManager = PlaybackManager()
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var nasServerStore: NASServerStore

    init() {
        let library = MockMusicLibraryProvider()
        musicLibrary = library

        let seedSongs = Array((library.albums.flatMap(\.songs) + library.standaloneSongs).prefix(4))
        let seedDownloads = seedSongs.enumerated().map { index, song -> DownloadItem in
            let status: DownloadStatus = index == 0 ? .completed : (index == 1 ? .failed : .downloading)
            let progress: Double = index == 0 ? 1 : (index == 1 ? 0.4 : 0.15 * Double(index))
            return DownloadItem(id: "download-\(song.id)", song: song, status: status, progress: progress)
        }
        _downloadManager = StateObject(wrappedValue: DownloadManager(items: seedDownloads))

        let seedServers = [
            NASServerProfile(
                id: "nas-home",
                name: "群晖 NAS（家庭）",
                host: "192.168.1.10",
                port: 5001,
                username: "admin",
                useQuickConnect: false,
                status: .connected
            ),
            NASServerProfile(
                id: "nas-quickconnect",
                name: "群晖 NAS（QuickConnect）",
                host: "mynas.quickconnect.to",
                port: 5001,
                username: "wuchang",
                useQuickConnect: true,
                status: .disconnected
            ),
        ]
        _nasServerStore = StateObject(wrappedValue: NASServerStore(servers: seedServers))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                musicLibrary: musicLibrary,
                playbackManager: playbackManager,
                downloadManager: downloadManager,
                nasServerStore: nasServerStore
            )
        }
    }
}
