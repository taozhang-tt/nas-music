//
//  AudioStationError.swift
//  nas-music
//
//  SynologyAudioStationProvider 的错误语义。区别于 SynologyAPIError（DSM 登录/连接层面），
//  这里是 Audio Station 业务层面的错误：套件未安装、接口不可用、媒体库为空、播放地址拿不到等。
//

import Foundation

enum AudioStationError: LocalizedError, Equatable {
    case audioStationNotInstalled
    case apiUnavailable(String)
    case emptyLibrary
    case invalidSongId
    case streamURLUnavailable
    case permissionDenied
    case sessionExpired
    case unsupportedResponse
    case decodingFailed
    case networkError(SynologyAPIError)

    var errorDescription: String? {
        switch self {
        case .audioStationNotInstalled:
            return "当前 NAS 未检测到 Audio Station，请先在群晖套件中心安装并启用 Audio Station。"
        case .apiUnavailable:
            return "当前 Audio Station 接口不可用，请确认 DSM / Audio Station 版本是否支持该功能。"
        case .emptyLibrary:
            return "没有找到音乐文件。请确认 Audio Station 已完成音乐索引。"
        case .permissionDenied:
            return "当前账号没有访问 Audio Station 音乐库的权限。"
        case .sessionExpired:
            return "登录状态已过期，请重新连接 NAS。"
        case .streamURLUnavailable:
            return "无法获取歌曲播放地址，请稍后重试。"
        case .invalidSongId:
            return "歌曲信息不完整，无法播放。"
        case .unsupportedResponse:
            return "NAS 返回了无法识别的响应，请稍后重试。"
        case .decodingFailed:
            return "解析 Audio Station 响应失败，请稍后重试。"
        case .networkError(let underlying):
            return underlying.localizedDescription
        }
    }

    static func == (lhs: AudioStationError, rhs: AudioStationError) -> Bool {
        switch (lhs, rhs) {
        case (.audioStationNotInstalled, .audioStationNotInstalled),
             (.emptyLibrary, .emptyLibrary),
             (.invalidSongId, .invalidSongId),
             (.streamURLUnavailable, .streamURLUnavailable),
             (.permissionDenied, .permissionDenied),
             (.sessionExpired, .sessionExpired),
             (.unsupportedResponse, .unsupportedResponse),
             (.decodingFailed, .decodingFailed):
            return true
        case (.apiUnavailable(let a), .apiUnavailable(let b)):
            return a == b
        case (.networkError(let a), .networkError(let b)):
            return a == b
        default:
            return false
        }
    }
}
