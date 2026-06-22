//
//  DatabaseError.swift
//  nas-music
//

import Foundation

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "打开本地音乐库失败：\(message)"
        case .prepareFailed(let message):
            return "准备数据库语句失败：\(message)"
        case .stepFailed(let message):
            return "执行数据库语句失败：\(message)"
        case .bindFailed(let message):
            return "绑定数据库参数失败：\(message)"
        case .migrationFailed(let message):
            return "迁移本地音乐库失败：\(message)"
        }
    }
}
