//
//  NASConnectionConfig.swift
//  nas-music
//
//  NAS 连接的非敏感配置。密码/sid/synotoken 不出现在这个模型里，
//  只能临时存在于登录表单内存中或 Keychain（见 NASCredentialStore）。
//

import Foundation

struct NASConnectionConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var useHTTPS: Bool
    var username: String
    var displayName: String?
    var lastConnectedAt: Date?
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 5001,
        useHTTPS: Bool = true,
        username: String,
        displayName: String? = nil,
        lastConnectedAt: Date? = nil,
        isDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.useHTTPS = useHTTPS
        self.username = username
        self.displayName = displayName
        self.lastConnectedAt = lastConnectedAt
        self.isDefault = isDefault
    }
}
