//
//  NASServerProfile.swift
//  nas-music
//

import Foundation

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case testing

    var label: String {
        switch self {
        case .connected: "已连接"
        case .disconnected: "未连接"
        case .testing: "正在连接…"
        }
    }
}

struct NASServerProfile: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    var useQuickConnect: Bool
    var status: ConnectionStatus

    static func == (lhs: NASServerProfile, rhs: NASServerProfile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
