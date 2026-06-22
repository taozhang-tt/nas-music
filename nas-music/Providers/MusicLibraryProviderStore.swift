//
//  MusicLibraryProviderStore.swift
//  nas-music
//
//  统一决定首页/音乐库/专辑详情/PlaybackManager 当前应该用哪个 MusicLibraryProvider：
//  NAS 已连接时用 SynologyAudioStationProvider，否则回退到 MockMusicLibraryProvider。
//  Audio Station 报告会话失效时，通过 sessionManager.clearCredentials() 清掉本地凭证并
//  把状态标记为 disconnected，store 会随之自动切回 Mock provider。
//

import Foundation
import Combine

@MainActor
final class MusicLibraryProviderStore: ObservableObject {
    @Published private(set) var activeProvider: MusicLibraryProvider
    @Published private(set) var isUsingSynology = false

    private let sessionManager: NASSessionManager
    private let mockProvider: MockMusicLibraryProvider
    private var cancellable: AnyCancellable?

    init(sessionManager: NASSessionManager, mockProvider: MockMusicLibraryProvider = MockMusicLibraryProvider()) {
        self.sessionManager = sessionManager
        self.mockProvider = mockProvider
        self.activeProvider = mockProvider
        cancellable = sessionManager.$state.sink { [weak self] state in
            self?.handle(state: state)
        }
        handle(state: sessionManager.state)
    }

    var connectionState: NASConnectionState { sessionManager.state }
    var nasDisplayName: String? { sessionManager.config?.displayName ?? sessionManager.config?.name }
    var lastConnectedAt: Date? { sessionManager.config?.lastConnectedAt }

    private func handle(state: NASConnectionState) {
        guard let config = sessionManager.config else {
            activeProvider = mockProvider
            isUsingSynology = false
            ArtworkImageLoader.shared.updateProvider(MockArtworkProvider(), nasIdentifier: "mock")
            return
        }

        let provider = SynologyAudioStationProvider(config: config)
        provider.onSessionExpired = { [weak sessionManager] in
            sessionManager?.clearCredentials()
        }
        let appService = AppMusicLibraryService(sessionManager: sessionManager, remoteProvider: provider, mockProvider: mockProvider)
        activeProvider = AppMusicLibraryProvider(service: appService)
        isUsingSynology = true

        switch state {
        case .connected:
            let artworkProvider = SynologyArtworkProvider(config: config)
            artworkProvider.onSessionExpired = { [weak sessionManager] in
                sessionManager?.clearCredentials()
            }
            ArtworkImageLoader.shared.updateProvider(artworkProvider, nasIdentifier: config.id.uuidString)
        case .disconnected, .connecting, .failed:
            ArtworkImageLoader.shared.updateProvider(MockArtworkProvider(), nasIdentifier: "mock")
        }
    }
}
