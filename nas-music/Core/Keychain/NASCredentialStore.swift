//
//  NASCredentialStore.swift
//  nas-music
//
//  NAS 登录凭证（username/sid/synotoken/deviceId）的 Keychain 存取，按 configId 隔离。
//  绝不存明文密码——密码只活在登录表单内存里，登录成功后立即丢弃。
//

import Foundation

struct NASCredential: Codable, Equatable {
    let username: String
    let sid: String
    let synoToken: String?
    let deviceId: String?
}

struct NASCredentialStore {
    private let keychain: KeychainService

    init(keychain: KeychainService = KeychainService(service: "zero-tt.top.nas-music.nascredential")) {
        self.keychain = keychain
    }

    func saveCredential(configId: UUID, username: String, sid: String, synoToken: String?, deviceId: String? = nil) throws {
        let credential = NASCredential(username: username, sid: sid, synoToken: synoToken, deviceId: deviceId)
        let data = try JSONEncoder().encode(credential)
        try keychain.save(data, account: configId.uuidString)
    }

    func readCredential(configId: UUID) -> NASCredential? {
        guard let data = try? keychain.read(account: configId.uuidString) else { return nil }
        return try? JSONDecoder().decode(NASCredential.self, from: data)
    }

    func deleteCredential(configId: UUID) {
        try? keychain.delete(account: configId.uuidString)
    }

    func deleteAllCredentials() {
        try? keychain.deleteAll()
    }
}
