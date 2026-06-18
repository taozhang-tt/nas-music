//
//  ArtworkError.swift
//  nas-music
//
//  封面加载/缓存相关的错误语义。和 AudioStationError 一样，UI 层基本只用来决定
//  「静默回退默认封面」还是「在设置页展示具体错误」，不会弹大量 toast。
//

import Foundation

enum ArtworkError: LocalizedError, Equatable {
    case missingCoverId
    case apiUnavailable
    case sessionExpired
    case invalidImageData
    case networkError(SynologyAPIError)
    case diskWriteFailed
    case diskReadFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingCoverId:
            return "没有封面信息。"
        case .apiUnavailable:
            return "当前 Audio Station 不支持封面接口。"
        case .sessionExpired:
            return "登录状态已过期，请重新连接 NAS。"
        case .invalidImageData:
            return "封面数据无效。"
        case .networkError(let underlying):
            return underlying.localizedDescription
        case .diskWriteFailed:
            return "封面缓存写入失败。"
        case .diskReadFailed:
            return "封面缓存读取失败。"
        case .unknown:
            return "未知错误，请稍后重试。"
        }
    }

    static func == (lhs: ArtworkError, rhs: ArtworkError) -> Bool {
        switch (lhs, rhs) {
        case (.missingCoverId, .missingCoverId),
             (.apiUnavailable, .apiUnavailable),
             (.sessionExpired, .sessionExpired),
             (.invalidImageData, .invalidImageData),
             (.diskWriteFailed, .diskWriteFailed),
             (.diskReadFailed, .diskReadFailed),
             (.unknown, .unknown):
            return true
        case (.networkError(let a), .networkError(let b)):
            return a == b
        default:
            return false
        }
    }
}
