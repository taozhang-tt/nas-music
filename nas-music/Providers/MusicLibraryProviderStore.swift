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
        switch state {
        case .connected:
            guard let config = sessionManager.config else {
                activeProvider = mockProvider
                isUsingSynology = false
                return
            }
            let provider = SynologyAudioStationProvider(config: config)
            provider.onSessionExpired = { [weak sessionManager] in
                sessionManager?.clearCredentials()
            }
            activeProvider = provider
            isUsingSynology = true
        case .disconnected, .connecting, .failed:
            activeProvider = mockProvider
            isUsingSynology = false
        }
    }
}
