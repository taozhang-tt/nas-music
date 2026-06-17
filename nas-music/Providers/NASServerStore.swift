//
//  NASServerStore.swift
//  nas-music
//
//  Mock 的 NAS 服务器列表与连接测试，不接入真实网络。
//

import Foundation
import Combine

@MainActor
final class NASServerStore: ObservableObject {
    @Published private(set) var servers: [NASServerProfile]

    init(servers: [NASServerProfile]) {
        self.servers = servers
    }

    func testConnection(for server: NASServerProfile) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].status = .testing
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard let currentIndex = servers.firstIndex(where: { $0.id == server.id }) else { return }
            servers[currentIndex].status = Double.random(in: 0...1) < 0.85 ? .connected : .disconnected
        }
    }
}
