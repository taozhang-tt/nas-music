//
//  AppLogger.swift
//  nas-music
//
//  统一的日志出口。debug 模式可以打印请求路径/状态码/错误码，但 passwd/sid/synotoken
//  这几个 key 永远只打印 <redacted>，Release 编译里直接不调用底层 Logger，减少日志输出。
//

import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = "zero-tt.top.nas-music"
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let session = Logger(subsystem: subsystem, category: "Session")

    private static let sensitiveKeys: Set<String> = ["passwd", "password", "sid", "_sid", "synotoken"]

    static func logRequest(method: String, path: String, queryItems: [URLQueryItem]) {
        #if DEBUG
        let redacted = queryItems
            .map { item in isSensitive(item.name) ? "\(item.name)=<redacted>" : "\(item.name)=\(item.value ?? "")" }
            .joined(separator: "&")
        network.debug("\(method, privacy: .public) \(path, privacy: .public)?\(redacted, privacy: .public)")
        #endif
    }

    static func logResponse(statusCode: Int, apiErrorCode: Int?) {
        #if DEBUG
        if let apiErrorCode {
            network.debug("response status=\(statusCode, privacy: .public) apiErrorCode=\(apiErrorCode, privacy: .public)")
        } else {
            network.debug("response status=\(statusCode, privacy: .public) success")
        }
        #endif
    }

    private static func isSensitive(_ key: String) -> Bool {
        sensitiveKeys.contains(key.lowercased())
    }
}
