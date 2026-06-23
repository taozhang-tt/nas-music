//
//  MetadataWritebackError.swift
//  nas-music
//

import Foundation

enum MetadataWritebackError: LocalizedError, Equatable {
    case agentUnavailable
    case agentNotConfigured
    case unauthorized
    case songNotFound
    case pathNotAllowed
    case permissionDenied
    case unsupportedFormat
    case fileChanged
    case fileLocked
    case insufficientSpace
    case backupFailed
    case tagWriteFailed
    case validationFailed
    case replacementFailed
    case rollbackFailed
    case indexingPending
    case invalidResponse
    case invalidSongSource
    case serverMessage(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .agentUnavailable:
            return "无法连接 NASMusic Agent，请检查 Agent 地址和网络。"
        case .agentNotConfigured:
            return "请先配置 NASMusic Agent。"
        case .unauthorized:
            return "NASMusic Agent 认证失败，请检查 API Token。"
        case .songNotFound:
            return "Agent 未找到这首歌曲对应的音乐文件。"
        case .pathNotAllowed:
            return "Agent 拒绝访问该音乐文件路径。"
        case .permissionDenied:
            return "NASMusic Agent 没有修改该音乐文件的权限。"
        case .unsupportedFormat:
            return "当前音乐格式暂不支持安全修改标签。"
        case .fileChanged:
            return "该音乐文件已被其他用户修改，请重新加载后再保存。"
        case .fileLocked:
            return "该音乐文件正在被其他写入任务处理，请稍后重试。"
        case .insufficientSpace:
            return "NAS 可用空间不足，无法创建临时文件或备份。"
        case .backupFailed:
            return "创建修改前备份失败，已取消写入。"
        case .tagWriteFailed:
            return "写入音乐标签失败，原文件未被替换。"
        case .validationFailed:
            return "写入后校验失败，原文件未被替换。"
        case .replacementFailed:
            return "替换原音乐文件失败，请检查 NAS 文件权限。"
        case .rollbackFailed:
            return "恢复上一次修改失败。"
        case .indexingPending:
            return "文件标签已经修改，正在等待群晖更新音乐索引。"
        case .invalidResponse:
            return "NASMusic Agent 返回了无法识别的响应。"
        case .invalidSongSource:
            return "这首歌曲不是可写回的 NAS 音乐。"
        case .serverMessage(let message):
            return message
        case .unknown:
            return "标签写回失败，请稍后重试。"
        }
    }
}
