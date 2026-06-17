//
//  SynologyAuthService.swift
//  nas-music
//
//  SYNO.API.Auth 的业务逻辑：查询 API 版本范围、登录、登出、以及用于「测试连接」的
//  登录后立即登出。DSM 的 error.code 在这里翻译成 SynologyAPIError。
//

import Foundation

struct SynologyAPIInfo {
    let path: String
    let minVersion: Int
    let maxVersion: Int
}

struct SynologyLoginResult {
    let sid: String
    let synoToken: String?
    let deviceId: String?
}

struct SynologyAuthService {
    private let client: SynologyAPIClient
    private let preferredVersion = 6

    init(client: SynologyAPIClient) {
        self.client = client
    }

    func queryAuthAPIInfo() async throws -> SynologyAPIInfo {
        let data = try await client.get(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Info"),
                URLQueryItem(name: "version", value: "1"),
                URLQueryItem(name: "method", value: "query"),
                URLQueryItem(name: "query", value: "SYNO.API.Auth"),
            ]
        )

        let response: SynologyAPIInfoResponse
        do {
            response = try JSONDecoder().decode(SynologyAPIInfoResponse.self, from: data)
        } catch {
            throw SynologyAPIError.decodingFailed
        }

        guard response.success, let entry = response.data?["SYNO.API.Auth"] else {
            AppLogger.logResponse(statusCode: 200, apiErrorCode: response.error?.code)
            throw SynologyAPIError.apiNotFound
        }
        return SynologyAPIInfo(path: entry.path, minVersion: entry.minVersion, maxVersion: entry.maxVersion)
    }

    func login(username: String, password: String) async throws -> SynologyLoginResult {
        let info = try await queryAuthAPIInfo()
        let version = min(max(preferredVersion, info.minVersion), info.maxVersion)

        let data = try await client.get(
            path: "/webapi/\(info.path)",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Auth"),
                URLQueryItem(name: "version", value: String(version)),
                URLQueryItem(name: "method", value: "login"),
                URLQueryItem(name: "account", value: username),
                URLQueryItem(name: "passwd", value: password),
                URLQueryItem(name: "enable_syno_token", value: "yes"),
            ]
        )

        let response: SynologyLoginResponse
        do {
            response = try JSONDecoder().decode(SynologyLoginResponse.self, from: data)
        } catch {
            throw SynologyAPIError.decodingFailed
        }

        AppLogger.logResponse(statusCode: 200, apiErrorCode: response.error?.code)

        guard response.success, let loginData = response.data else {
            throw Self.mapErrorCode(response.error?.code)
        }

        return SynologyLoginResult(sid: loginData.sid, synoToken: loginData.synotoken, deviceId: loginData.did)
    }

    func logout(sid: String) async {
        _ = try? await client.get(
            path: "/webapi/entry.cgi",
            queryItems: [
                URLQueryItem(name: "api", value: "SYNO.API.Auth"),
                URLQueryItem(name: "version", value: "6"),
                URLQueryItem(name: "method", value: "logout"),
                URLQueryItem(name: "_sid", value: sid),
            ]
        )
    }

    /// 仅用于「测试连接」：登录成功后立即登出，不在这一层做任何持久化。
    func testConnection(username: String, password: String) async throws {
        let result = try await login(username: username, password: password)
        await logout(sid: result.sid)
    }

    private static func mapErrorCode(_ code: Int?) -> SynologyAPIError {
        guard let code else { return .invalidResponse }
        switch code {
        case 400:
            return .invalidCredential
        case 401, 402:
            return .permissionDenied
        case 403, 404:
            return .twoFactorRequired
        case 106, 119:
            return .sessionExpired
        case 102, 103:
            return .apiNotFound
        case 104:
            return .unsupportedVersion
        default:
            return .unknownSynologyError(code: code)
        }
    }
}
