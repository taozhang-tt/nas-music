//
//  nas_musicApp.swift
//  nas-music
//
//  Created by wuchang on 2026/6/17.
//
//  组合根：创建 NASSessionManager + MusicLibraryProviderStore（NAS 已连接时自动切换到
//  SynologyAudioStationProvider，否则用 MockMusicLibraryProvider），PlaybackManager 通过
//  .environmentObject 全局注入，并订阅 providerStore 切换时同步更新 PlaybackManager 用来
//  解析 stream URL 的 provider。
//

import SwiftUI
import Combine

@main
struct nas_musicApp: App {
    @StateObject private var playbackManager: PlaybackManager
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var nasSessionManager: NASSessionManager
    @StateObject private var providerStore: MusicLibraryProviderStore
    @StateObject private var musicLibrarySyncService: MusicLibrarySyncService
    private let nowPlayingInfoManager: NowPlayingInfoManager
    private let remoteCommandManager: RemoteCommandManager
    private let providerStoreObserver: AnyCancellable?

    init() {
        let sessionManager = NASSessionManager()
        _nasSessionManager = StateObject(wrappedValue: sessionManager)
        _musicLibrarySyncService = StateObject(wrappedValue: MusicLibrarySyncService(sessionManager: sessionManager))

        let store = MusicLibraryProviderStore(sessionManager: sessionManager)
        _providerStore = StateObject(wrappedValue: store)

        let playbackManager = PlaybackManager(audioSessionManager: AudioSessionManager(), musicLibraryProvider: store.activeProvider)
        _playbackManager = StateObject(wrappedValue: playbackManager)
        nowPlayingInfoManager = NowPlayingInfoManager(playbackManager: playbackManager)
        remoteCommandManager = RemoteCommandManager(playbackManager: playbackManager)
        providerStoreObserver = store.$activeProvider.sink { provider in
            playbackManager.updateMusicLibraryProvider(provider)
        }

        let mockProvider = MockMusicLibraryProvider()
        let seedSongs = Array(mockProvider.songs.prefix(4))
        let seedDownloads = seedSongs.enumerated().map { index, song -> DownloadItem in
            let status: DownloadStatus = index == 0 ? .completed : (index == 1 ? .failed : .downloading)
            let progress: Double = index == 0 ? 1 : (index == 1 ? 0.4 : 0.15 * Double(index))
            return DownloadItem(id: "download-\(song.id)", song: song, status: status, progress: progress)
        }
        _downloadManager = StateObject(wrappedValue: DownloadManager(items: seedDownloads))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                providerStore: providerStore,
                downloadManager: downloadManager,
                nasSessionManager: nasSessionManager,
                musicLibrarySyncService: musicLibrarySyncService
            )
            .environmentObject(playbackManager)
        }
    }
}
