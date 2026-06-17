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

    /// API Discovery 诊断日志：只打印 API 名称/path/版本范围，不涉及任何鉴权信息。
    static func logDiscoveredAPI(name: String, path: String, minVersion: Int, maxVersion: Int) {
        #if DEBUG
        network.debug("discovered api=\(name, privacy: .public) path=\(path, privacy: .public) minVersion=\(minVersion, privacy: .public) maxVersion=\(maxVersion, privacy: .public)")
        #endif
    }

    /// Audio Station 业务响应诊断日志：只打印 api 名称/success/群晖 error code/耗时。
    static func logAudioStationResponse(api: String, success: Bool, errorCode: Int?, elapsed: TimeInterval) {
        #if DEBUG
        let elapsedMs = Int(elapsed * 1000)
        if let errorCode {
            network.debug("audiostation api=\(api, privacy: .public) success=\(success, privacy: .public) errorCode=\(errorCode, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")
        } else {
            network.debug("audiostation api=\(api, privacy: .public) success=\(success, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")
        }
        #endif
    }

    private static func isSensitive(_ key: String) -> Bool {
        sensitiveKeys.contains(key.lowercased())
    }
}
