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

    func get(path: String, queryItems: [URLQueryItem], headers: [String: String] = [:]) async throws -> Data {
        let url = try makeURL(path: path, queryItems: queryItems)

        AppLogger.logRequest(method: "GET", path: url.path, queryItems: queryItems)

        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.data(for: request)
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

    /// 构建请求 URL 但不发起请求——用于像 SYNO.AudioPlayer.Stream 这样本身就是二进制流地址的
    /// 接口，交给 AVPlayer 自己去加载，不需要 SynologyAPIClient 先 GET 一遍。
    func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SynologyAPIError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SynologyAPIError.invalidURL }
        return url
    }

    /// SYNO.API.Info 的批量查询：返回的字典只包含 NAS 实际支持的 API，调用方应该把
    /// 字典里找不到的 API 当作 unavailable，而不是假设它一定存在。
    func queryAPIInfo(_ apis: [String]) async throws -> [String: SynologyAPIInfo] {
        let data = try await get(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Info"),
                URLQueryItem(name: "version", value: "1"),
                URLQueryItem(name: "method", value: "query"),
                URLQueryItem(name: "query", value: apis.joined(separator: ",")),
            ]
        )

        let response: SynologyAPIInfoResponse
        do {
            response = try JSONDecoder().decode(SynologyAPIInfoResponse.self, from: data)
        } catch {
            throw SynologyAPIError.decodingFailed
        }

        guard response.success, let entries = response.data else {
            throw SynologyAPIError.apiNotFound
        }

        var result: [String: SynologyAPIInfo] = [:]
        for api in apis {
            guard let entry = entries[api] else { continue }
            let info = SynologyAPIInfo(path: entry.path, minVersion: entry.minVersion, maxVersion: entry.maxVersion)
            result[api] = info
            AppLogger.logDiscoveredAPI(name: api, path: info.path, minVersion: info.minVersion, maxVersion: info.maxVersion)
        }
        return result
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
