//
//  SynologyAPIError.swift
//  nas-music
//

import Foundation

enum SynologyAPIError: Error, Equatable {
    case invalidHost
    case invalidPort
    case invalidURL
    case networkUnavailable
    case timeout
    case sslError
    case invalidCredential
    case twoFactorRequired
    case permissionDenied
    case sessionExpired
    case apiNotFound
    case unsupportedVersion
    case unknownSynologyError(code: Int)
    case invalidResponse
    case decodingFailed
}

extension SynologyAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "NAS 地址不正确，请检查主机地址。"
        case .invalidPort:
            return "端口不正确，请检查端口号。"
        case .invalidURL:
            return "无法构建有效的连接地址，请检查地址和端口。"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接。"
        case .timeout:
            return "连接超时，请确认手机和 NAS 是否在同一网络，或检查端口是否开放。"
        case .sslError:
            return "无法验证 NAS 的 HTTPS 证书。请确认群晖证书是否有效，或暂时使用局域网 HTTP 测试。"
        case .invalidCredential:
            return "账号或密码错误，请检查后重试。"
        case .twoFactorRequired:
            return "当前账号开启了二次验证，本版本暂不支持 2FA 登录，请先使用普通测试账号或等待后续版本支持。"
        case .permissionDenied:
            return "账号没有权限访问，请联系管理员检查账号状态。"
        case .sessionExpired:
            return "登录状态已过期，请重新登录。"
        case .apiNotFound:
            return "当前 NAS 未返回 DSM 登录 API，请确认 DSM 版本和地址是否正确。"
        case .unsupportedVersion:
            return "当前 NAS 的 DSM 版本不受支持，请升级 DSM 或反馈给开发者。"
        case .unknownSynologyError(let code):
            return "群晖返回未知错误（错误码 \(code)），请稍后重试。"
        case .invalidResponse:
            return "NAS 返回了无法识别的响应，请稍后重试。"
        case .decodingFailed:
            return "解析 NAS 响应失败，请稍后重试。"
        }
    }
}
