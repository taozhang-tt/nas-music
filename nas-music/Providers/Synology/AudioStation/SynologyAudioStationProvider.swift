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
import OSLog

final class SynologyAudioStationProvider: MusicLibraryProvider {
    private static let logger = Logger(subsystem: "zero-tt.top.nas-music", category: "AudioStation")

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
        "SYNO.AudioStation.Stream",
        "SYNO.AudioStation.Download",
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
                URLQueryItem(name: "additional", value: "song_tag,song_audio,album_tag,cover,song_path,path"),
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
                URLQueryItem(name: "additional", value: "song_count,cover"),
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

    /// 用 discovery 得到的候选 stream/download API 逐个探测，只有确认返回音频/二进制媒体时才
    /// 交给 AVPlayer。不同 DSM / Audio Station 版本的播放接口差异很大，不能固定猜一个 method。
    func fetchStreamURL(for song: Song) async throws -> URL {
        try await fetchStreamResource(for: song).url
    }

    func fetchStreamResource(for song: Song) async throws -> PlaybackStreamResource {
        guard let audioStationId = song.audioStationId else {
            throw AudioStationError.invalidSongId
        }
        let credential = try currentCredential()
        let client = try makeClient()
        let infos = try await discoverAPIs()
        var headers: [String: String] = [:]
        if let synoToken = credential.synoToken {
            headers["X-SYNO-TOKEN"] = synoToken
        }

        var candidates: [StreamCandidate] = []
        addCandidate(
            &candidates,
            api: "SYNO.AudioStation.Stream",
            info: infos["SYNO.AudioStation.Stream"],
            method: "stream",
            idParameterName: "id",
            songId: audioStationId,
            sid: credential.sid
        )
        addCandidate(
            &candidates,
            api: "SYNO.AudioStation.Download",
            info: infos["SYNO.AudioStation.Download"],
            method: "download",
            idParameterName: "id",
            songId: audioStationId,
            sid: credential.sid
        )
        addCandidate(
            &candidates,
            api: "SYNO.AudioStation.Song",
            info: infos["SYNO.AudioStation.Song"],
            method: "stream",
            idParameterName: "id",
            songId: audioStationId,
            sid: credential.sid
        )
        addCandidate(
            &candidates,
            api: "SYNO.AudioStation.Song",
            info: infos["SYNO.AudioStation.Song"],
            method: "download",
            idParameterName: "id",
            songId: audioStationId,
            sid: credential.sid
        )
        addCandidate(
            &candidates,
            api: "SYNO.AudioPlayer.Stream",
            info: infos["SYNO.AudioPlayer.Stream"],
            method: "stream",
            idParameterName: "id",
            songId: audioStationId,
            sid: credential.sid
        )

        for candidate in candidates {
            do {
                let url = try client.makeURL(path: candidate.path, queryItems: candidate.queryItems)
                if try await probeStreamCandidate(url, headers: headers, label: candidate.label) {
                    Self.logger.debug("stream candidate selected label=\(candidate.label, privacy: .public) path=\(candidate.path, privacy: .public)")
                    return PlaybackStreamResource(url: url, headers: headers)
                }
            } catch {
                Self.logger.debug("stream candidate failed label=\(candidate.label, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        throw AudioStationError.streamURLUnavailable
    }

    private struct StreamCandidate {
        let label: String
        let path: String
        let queryItems: [URLQueryItem]
    }

    private func addCandidate(
        _ candidates: inout [StreamCandidate],
        api: String,
        info: SynologyAPIInfo?,
        method: String,
        idParameterName: String,
        songId: String,
        sid: String
    ) {
        guard let info else { return }
        candidates.append(StreamCandidate(
            label: "\(api).\(method).\(idParameterName)",
            path: "/webapi/\(info.path)",
            queryItems: [
                URLQueryItem(name: "api", value: api),
                URLQueryItem(name: "version", value: String(info.maxVersion)),
                URLQueryItem(name: "method", value: method),
                URLQueryItem(name: idParameterName, value: songId),
                URLQueryItem(name: "_sid", value: sid),
            ]
        ))
    }

    private func probeStreamCandidate(_ url: URL, headers: [String: String], label: String) async throws -> Bool {
        let head = try await streamProbeRequest(url: url, method: "HEAD", headers: headers)
        guard (200..<300).contains(head.statusCode) else {
            Self.logger.debug("stream candidate head rejected label=\(label, privacy: .public) status=\(head.statusCode, privacy: .public)")
            return false
        }
        if isClearlyPlayable(contentType: head.contentType) {
            return true
        }
        if isClearlyText(contentType: head.contentType) || head.contentType == nil {
            let get = try await streamProbeRequest(url: url, method: "GET", headers: headers)
            if let jsonMessage = jsonProbeErrorMessage(from: get.data) {
                Self.logger.debug("stream candidate json label=\(label, privacy: .public) message=\(jsonMessage, privacy: .public)")
                return false
            }
            return looksLikeAudio(get.data) || !looksLikePrintableText(get.data.prefix(64))
        }
        return true
    }

    private struct StreamProbeResponse {
        let statusCode: Int
        let contentType: String?
        let data: Data
    }

    private func streamProbeRequest(url: URL, method: String, headers: [String: String]) async throws -> StreamProbeResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if method == "GET" {
            request.setValue("bytes=0-63", forHTTPHeaderField: "Range")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AudioStationError.unsupportedResponse
        }
        return StreamProbeResponse(statusCode: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), data: data)
    }

    private func isClearlyPlayable(contentType: String?) -> Bool {
        let contentType = contentType?.lowercased() ?? ""
        return contentType.hasPrefix("audio/")
            || contentType == "application/octet-stream"
            || contentType == "binary/octet-stream"
            || contentType.contains("mpeg")
            || contentType.contains("flac")
    }

    private func isClearlyText(contentType: String?) -> Bool {
        let contentType = contentType?.lowercased() ?? ""
        return contentType.contains("text/")
            || contentType.contains("json")
            || contentType.contains("xml")
    }

    private func looksLikeAudio(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(16))
        guard bytes.count >= 2 else { return false }
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return true }
        if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 { return true }
        if bytes.count >= 4, bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 { return true }
        if bytes.count >= 4, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 { return true }
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return true }
        if bytes.count >= 4, bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53 { return true }
        return false
    }

    private func looksLikePrintableText(_ data: Data.SubSequence) -> Bool {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return false }
        let printableCount = bytes.filter { byte in
            byte == 0x09 || byte == 0x0A || byte == 0x0D || (0x20...0x7E).contains(byte)
        }.count
        return Double(printableCount) / Double(bytes.count) > 0.85
    }

    private func jsonProbeErrorMessage(from data: Data) -> String? {
        struct ProbeAPIError: Decodable {
            let code: Int?
        }
        struct ProbeAPIResponse: Decodable {
            let success: Bool?
            let error: ProbeAPIError?
        }
        guard let response = try? JSONDecoder().decode(ProbeAPIResponse.self, from: data) else {
            return nil
        }
        if let code = response.error?.code {
            return "Synology errorCode=\(code)"
        }
        if let success = response.success {
            return "success=\(success)"
        }
        return "JSON response"
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
