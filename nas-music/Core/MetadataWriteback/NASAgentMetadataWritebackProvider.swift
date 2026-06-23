//
//  NASAgentMetadataWritebackProvider.swift
//  nas-music
//

import Foundation

final class NASAgentMetadataWritebackProvider: MetadataWritebackProvider {
    private let baseURL: URL
    private let apiToken: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, apiToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func health() async throws -> MetadataAgentHealth {
        try await send(path: "/v1/health", method: "GET", body: Optional<String>.none)
    }

    func libraryIndexStatus() async throws -> MetadataLibraryIndexStatus {
        try await send(path: "/v1/library/index/status", method: "GET", body: Optional<String>.none)
    }

    func updateLibraryIndex(songs: [MetadataLibraryIndexSong]) async throws -> MetadataLibraryIndexUpdateResult {
        let body = LibraryIndexUpdateRequest(songs: songs)
        return try await send(path: "/v1/library/index", method: "PUT", body: body)
    }

    func readRemoteMetadata(for song: Song) async throws -> RemoteAudioMetadataEnvelope {
        let sourceId = try sourceId(for: song)
        return try await send(path: "/v1/songs/\(sourceId)/metadata", method: "GET", body: Optional<String>.none)
    }

    func previewUpdate(
        song: Song,
        patch: AudioMetadataPatch,
        convertToSimplified: Bool,
        fields: [String]
    ) async throws -> MetadataUpdatePreview {
        let sourceId = try sourceId(for: song)
        let body = PreviewRequest(convertToSimplified: convertToSimplified, fields: fields, manualPatch: patch)
        return try await send(path: "/v1/songs/\(sourceId)/metadata/preview", method: "POST", body: body)
    }

    func writeMetadata(song: Song, patch: AudioMetadataPatch, expectedRevision: String) async throws -> MetadataWriteResult {
        let sourceId = try sourceId(for: song)
        let body = WriteRequest(expectedRevision: expectedRevision, patch: patch, createBackup: true)
        return try await send(path: "/v1/songs/\(sourceId)/metadata", method: "PATCH", body: body)
    }

    func rollback(operationId: String) async throws {
        let escaped = operationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? operationId
        let _: EmptyResponse = try await send(path: "/v1/operations/\(escaped)/rollback", method: "POST", body: Optional<String>.none)
    }

    private func sourceId(for song: Song) throws -> String {
        guard let sourceId = song.audioStationId else { throw MetadataWritebackError.invalidSongSource }
        return sourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourceId
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw MetadataWritebackError.agentUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let response: URLResponse
        let data: Data
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MetadataWritebackError.agentUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataWritebackError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.error(for: httpResponse.statusCode, data: data, decoder: decoder)
        }
        if Response.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw MetadataWritebackError.serverMessage("NASMusic Agent 返回了解析失败的响应：\(error.localizedDescription)")
        }
    }

    private static func error(for statusCode: Int, data: Data, decoder: JSONDecoder) -> MetadataWritebackError {
        if let response = try? decoder.decode(AgentErrorResponse.self, from: data),
           !response.message.isEmpty {
            return .serverMessage(response.message)
        }
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 404:
            return .songNotFound
        case 409:
            return .fileChanged
        case 423:
            return .fileLocked
        case 415:
            return .unsupportedFormat
        case 507:
            return .insufficientSpace
        default:
            return .unknown
        }
    }
}

private struct AgentErrorResponse: Decodable {
    let error: String
    let message: String
}

private struct LibraryIndexUpdateRequest: Encodable {
    let songs: [MetadataLibraryIndexSong]
}

private struct PreviewRequest: Encodable {
    let convertToSimplified: Bool
    let fields: [String]
    let manualPatch: AudioMetadataPatch
}

private struct WriteRequest: Encodable {
    let expectedRevision: String
    let patch: AudioMetadataPatch
    let createBackup: Bool
}

private struct EmptyResponse: Codable {}
