//
//  SynologyAPIClient.swift
//  nas-music
//
//  最底层的 HTTP 调用：拼 baseURL、发 GET、把 URLError 翻译成 SynologyAPIError。
//  不关心 SYNO.API.Auth 的业务语义，那部分由 SynologyAuthService 负责。
//

import Foundation

struct SynologyAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(host: String, port: Int, useHTTPS: Bool, timeout: TimeInterval = 10) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { throw SynologyAPIError.invalidHost }
        guard (1...65535).contains(port) else { throw SynologyAPIError.invalidPort }

        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = trimmedHost
        components.port = port
        guard let url = components.url else { throw SynologyAPIError.invalidURL }
        baseURL = url

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SynologyAPIError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SynologyAPIError.invalidURL }

        AppLogger.logRequest(method: "GET", path: url.path, queryItems: queryItems)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw SynologyAPIError.invalidResponse
            }
            return data
        } catch let error as SynologyAPIError {
            throw error
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch {
            throw SynologyAPIError.networkUnavailable
        }
    }

    private static func mapURLError(_ error: URLError) -> SynologyAPIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return .sslError
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .networkUnavailable
        default:
            return .networkUnavailable
        }
    }
}
