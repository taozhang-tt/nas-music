//
//  SynologyArtworkProvider.swift
//  nas-music
//
//  接入真实 Audio Station 封面接口的 ArtworkProvider。优先通过 API Discovery 找
//  SYNO.AudioStation.Cover；这个 API 在已发布的 Synology 文档里没有官方的「降级」方案，
//  所以这里不去猜测 SYNO.AudioStation.Song/Album 上不存在的取图方法——Cover 不可用时
//  直接报 apiUnavailable，让上层回退到默认占位图，而不是发一堆很可能失败的探测请求。
//  Cover 接口成功时返回的是图片二进制；只有失败时才会是 { success:false, error } 这样的
//  JSON，所以这里靠「JSON 解码是否成功」来判断这次响应是不是错误。
//

import Foundation

final class SynologyArtworkProvider: ArtworkProvider {
    private let config: NASConnectionConfig
    private let credentialStore: NASCredentialStore
    private var cachedClient: SynologyAPIClient?
    private var apiInfoCache: [String: SynologyAPIInfo]?
    private var discoveryTask: Task<[String: SynologyAPIInfo], Error>?

    /// 会话失效时只通知外层（MusicLibraryProviderStore）去清理凭证，不在这里自动重试登录。
    var onSessionExpired: (() -> Void)?

    private static let discoveredAPINames = [
        "SYNO.AudioStation.Cover",
        "SYNO.AudioStation.Song",
        "SYNO.AudioStation.Album",
    ]

    init(config: NASConnectionConfig, credentialStore: NASCredentialStore = NASCredentialStore()) {
        self.config = config
        self.credentialStore = credentialStore
    }

    func fetchArtworkData(coverId: String, size: ArtworkSize) async throws -> Data {
        guard !coverId.isEmpty else { throw ArtworkError.missingCoverId }

        let info = try await coverAPIInfo()
        let credential = try currentCredential()
        let client = try makeClient()

        var headers: [String: String] = [:]
        if let synoToken = credential.synoToken {
            headers["X-SYNO-TOKEN"] = synoToken
        }

        let data: Data
        do {
            data = try await client.get(
                path: "/webapi/\(info.path)",
                queryItems: [
                    URLQueryItem(name: "api", value: "SYNO.AudioStation.Cover"),
                    URLQueryItem(name: "version", value: String(info.maxVersion)),
                    URLQueryItem(name: "method", value: "getcover"),
                    URLQueryItem(name: "id", value: coverId),
                    URLQueryItem(name: "size", value: size.rawValue),
                    URLQueryItem(name: "_sid", value: credential.sid),
                ],
                headers: headers
            )
        } catch let error as SynologyAPIError {
            throw mapNetworkError(error)
        }

        if let errorEnvelope = try? JSONDecoder().decode(SynologyCoverErrorEnvelope.self, from: data),
           !errorEnvelope.success {
            throw mapErrorCode(errorEnvelope.error?.code)
        }

        guard !data.isEmpty else { throw ArtworkError.invalidImageData }
        return data
    }

    // MARK: - Discovery

    private func coverAPIInfo() async throws -> SynologyAPIInfo {
        let infos = try await discoverAPIs()
        guard let info = infos["SYNO.AudioStation.Cover"] else { throw ArtworkError.apiUnavailable }
        return info
    }

    /// 并发的多个 fetch 调用会同时撞上 apiInfoCache == nil；用一个共享的 in-flight Task
    /// 把它们合并成一次真正的网络请求，而不是各发各的。
    private func discoverAPIs() async throws -> [String: SynologyAPIInfo] {
        if let apiInfoCache { return apiInfoCache }
        if let discoveryTask {
            return try await discoveryTask.value
        }

        let task = Task { try await self.requestAPIDiscovery() }
        discoveryTask = task
        defer { discoveryTask = nil }

        let result = try await task.value
        apiInfoCache = result
        return result
    }

    private func requestAPIDiscovery() async throws -> [String: SynologyAPIInfo] {
        let client = try makeClient()
        do {
            return try await client.queryAPIInfo(Self.discoveredAPINames)
        } catch let error as SynologyAPIError {
            throw mapNetworkError(error)
        }
    }

    // MARK: - Client / Credential

    private func makeClient() throws -> SynologyAPIClient {
        if let cachedClient { return cachedClient }
        do {
            let client = try SynologyAPIClient(host: config.host, port: config.port, useHTTPS: config.useHTTPS)
            cachedClient = client
            return client
        } catch let error as SynologyAPIError {
            throw mapNetworkError(error)
        }
    }

    private func currentCredential() throws -> NASCredential {
        guard let credential = credentialStore.readCredential(configId: config.id) else {
            throw ArtworkError.sessionExpired
        }
        return credential
    }

    // MARK: - Error mapping

    /// 群晖 Web API 通用错误码（100-119 段）：105 权限不足，106/107/119 都意味着会话已失效。
    private func mapErrorCode(_ code: Int?) -> ArtworkError {
        guard let code else { return .unknown }
        switch code {
        case 106, 107, 119:
            onSessionExpired?()
            return .sessionExpired
        case 101, 102, 103, 104:
            return .apiUnavailable
        default:
            return .unknown
        }
    }

    private func mapNetworkError(_ error: SynologyAPIError) -> ArtworkError {
        switch error {
        case .sessionExpired:
            onSessionExpired?()
            return .sessionExpired
        default:
            return .networkError(error)
        }
    }
}

private struct SynologyCoverErrorEnvelope: Decodable {
    let success: Bool
    let error: SynologyErrorPayload?
}
