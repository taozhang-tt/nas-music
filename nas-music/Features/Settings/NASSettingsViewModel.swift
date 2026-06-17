//
//  NASSettingsViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class NASSettingsViewModel: ObservableObject {
    @Published var rememberCredentialsInKeychain = true

    private let serverStore: NASServerStore
    private var cancellable: AnyCancellable?

    init(serverStore: NASServerStore) {
        self.serverStore = serverStore
        cancellable = serverStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var servers: [NASServerProfile] { serverStore.servers }

    func testConnection(for server: NASServerProfile) {
        serverStore.testConnection(for: server)
    }
}
