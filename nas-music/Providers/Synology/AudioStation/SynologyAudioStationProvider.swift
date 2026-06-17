//
//  SynologyAudioStationProvider.swift
//  nas-music
//
//  接入真实 Audio Station 的 MusicLibraryProvider 实现。每次请求都从 Keychain 现读
//  sid/synotoken（不在 init 时缓存凭证），API Discovery 结果按 provider 实例缓存一次——
//  并发的几个 fetch 调用共享同一个 in-flight Task，避免每个都各自再发一次 discovery 请求。
//  会话失效时只通过 onSessionExpired 回调通知外层清理凭证，不在这里自动重试登录。
//

import Foundation

final class SynologyAudioStationProvider: MusicLibraryProvider {
    private let config: NASConnectionConfig
    private let credentialStore: NASCredentialStore
    private var cachedClient: SynologyAPIClient?
    private var apiInfoCache: [String: SynologyAPIInfo]?
    private var discoveryTask: Task<[String: SynologyAPIInfo], Error>?

    /// Provider 不持有 NASSessionManager，避免反向依赖；会话失效时通过这个回调让外层
    /// （MusicLibraryProviderStore）调用 sessionManager.clearCredentials()。
    var onSessionExpired: (() -> Void)?

    private static let discoveredAPINames = [
        "SYNO.AudioStation.Info",
        "SYNO.AudioStation.Playlist",
        "SYNO.AudioStation.Folder",
        "SYNO.AudioStation.Song",
        "SYNO.AudioStation.Album",
        "SYNO.AudioStation.Artist",
        "SYNO.AudioPlayer.Stream",
    ]

    init(config: NASConnectionConfig, credentialStore: NASCredentialStore = NASCredentialStore()) {
        self.config = config
        self.credentialStore = credentialStore
    }

    func fetchSongs(offset: Int, limit: Int) async throws -> [Song] {
        let response: SynologyAudioStationSongListResponse = try await fetchList(
            api: "SYNO.AudioStation.Song",
            extraItems: [
                URLQueryItem(name: "method", value: "list"),
                URLQueryItem(name: "library", value: "all"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "additional", value: "song_tag,song_audio,album_tag"),
            ]
        )
        return (response.data?.songs ?? []).map(AudioStationMapper.song)
    }

    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album] {
        let response: SynologyAudioStationAlbumListResponse = try await fetchList(
            api: "SYNO.AudioStation.Album",
            extraItems: [
                URLQueryItem(name: "method", value: "list"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "additional", value: "song_count"),
            ]
        )
        return (response.data?.albums ?? []).map(AudioStationMapper.album)
    }

    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist] {
        let response: SynologyAudioStationArtistListResponse = try await fetchList(
            api: "SYNO.AudioStation.Artist",
            extraItems: [
                URLQueryItem(name: "method", value: "list"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "additional", value: "song_count"),
            ]
        )
        return (response.data?.artists ?? []).map(AudioStationMapper.artist)
    }

    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist] {
        let response: SynologyAudioStationPlaylistListResponse = try await fetchList(
            api: "SYNO.AudioStation.Playlist",
            extraItems: [
                URLQueryItem(name: "method", value: "list"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "additional", value: "song_count"),
            ]
        )
        return (response.data?.playlists ?? []).map(AudioStationMapper.playlist)
    }

    /// 优先用 discovery 给的 SYNO.AudioPlayer.Stream path/maxVersion；如果这个 API 本身没在
    /// discovery 结果里（但 Audio Station 本身是装了的），退回 entry.cgi + version 2。
    /// Stream 接口本身就是二进制流地址，这里只构造 URL，不发起请求——交给 AVPlayer 去加载。
    func fetchStreamURL(for song: Song) async throws -> URL {
        guard let audioStationId = song.audioStationId else {
            throw AudioStationError.invalidSongId
        }
        let credential = try currentCredential()
        let client = try makeClient()

        var path = "/webapi/entry.cgi"
        var version = 2
        do {
            let info = try await apiInfo("SYNO.AudioPlayer.Stream")
            path = "/webapi/\(info.path)"
            version = info.maxVersion
        } catch let error as AudioStationError {
            if case .apiUnavailable = error {
                // 用 entry.cgi + version 2 兜底
            } else {
                throw error
            }
        }

        do {
            return try client.makeURL(
                path: path,
                queryItems: [
                    URLQueryItem(name: "api", value: "SYNO.AudioPlayer.Stream"),
                    URLQueryItem(name: "version", value: String(version)),
                    URLQueryItem(name: "method", value: "stream"),
                    URLQueryItem(name: "id", value: audioStationId),
                    URLQueryItem(name: "_sid", value: credential.sid),
                ]
            )
        } catch let error as SynologyAPIError {
            throw AudioStationError.networkError(error)
        }
    }

    // MARK: - 通用 list 请求

    /// 统一负责：discovery -> 拼 api/version/_sid -> 请求 -> 解码 -> 记录诊断日志 -> success 判断。
    /// 调用方只需要给资源特有的参数（method/library/offset/limit/additional）。
    private func fetchList<Response: SynologyListResponse>(api: String, extraItems: [URLQueryItem]) async throws -> Response {
        let info = try await apiInfo(api)
        let credential = try currentCredential()
        let client = try makeClient()

        var items: [URLQueryItem] = [
            URLQueryItem(name: "api", value: api),
            URLQueryItem(name: "version", value: String(info.maxVersion)),
        ]
        items.append(contentsOf: extraItems)
        items.append(URLQueryItem(name: "_sid", value: credential.sid))

        var headers: [String: String] = [:]
        if let synoToken = credential.synoToken {
            headers["X-SYNO-TOKEN"] = synoToken
        }

        let start = Date()
        let data: Data
        do {
            data = try await client.get(path: "/webapi/\(info.path)", queryItems: items, headers: headers)
        } catch let error as SynologyAPIError {
            throw mapNetworkError(error)
        }
        let elapsed = Date().timeIntervalSince(start)

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            AppLogger.logAudioStationResponse(api: api, success: false, errorCode: nil, elapsed: elapsed)
            throw AudioStationError.decodingFailed
        }
        AppLogger.logAudioStationResponse(api: api, success: response.success, errorCode: response.error?.code, elapsed: elapsed)
        guard response.success else { throw mapErrorCode(response.error?.code) }
        return response
    }

    // MARK: - Discovery

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
        let result: [String: SynologyAPIInfo]
        do {
            result = try await client.queryAPIInfo(Self.discoveredAPINames)
        } catch let error as SynologyAPIError {
            throw mapNetworkError(error)
        }
        guard result["SYNO.AudioStation.Info"] != nil else {
            throw AudioStationError.audioStationNotInstalled
        }
        return result
    }

    private func apiInfo(_ name: String) async throws -> SynologyAPIInfo {
        let infos = try await discoverAPIs()
        guard let info = infos[name] else { throw AudioStationError.apiUnavailable(name) }
        return info
    }

    // MARK: - Client / Credential

    private func makeClient() throws -> SynologyAPIClient {
        if let cachedClient { return cachedClient }
        do {
            let client = try SynologyAPIClient(host: config.host, port: config.port, useHTTPS: config.useHTTPS)
            cachedClient = client
            return client
        } catch let error as SynologyAPIError {
            throw AudioStationError.networkError(error)
        }
    }

    private func currentCredential() throws -> NASCredential {
        guard let credential = credentialStore.readCredential(configId: config.id) else {
            throw AudioStationError.sessionExpired
        }
        return credential
    }

    // MARK: - Error mapping

    /// 群晖 Web API 通用错误码（100-119 段）：105 权限不足，106/107/119 都意味着会话已失效。
    private func mapErrorCode(_ code: Int?) -> AudioStationError {
        guard let code else { return .unsupportedResponse }
        switch code {
        case 105:
            return .permissionDenied
        case 106, 107, 119:
            onSessionExpired?()
            return .sessionExpired
        case 101, 102, 103, 104:
            return .apiUnavailable("error \(code)")
        default:
            return .unsupportedResponse
        }
    }

    private func mapNetworkError(_ error: SynologyAPIError) -> AudioStationError {
        switch error {
        case .sessionExpired:
            onSessionExpired?()
            return .sessionExpired
        case .permissionDenied:
            return .permissionDenied
        default:
            return .networkError(error)
        }
    }
}
