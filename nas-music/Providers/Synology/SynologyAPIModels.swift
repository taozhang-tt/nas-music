//
//  SynologyAPIModels.swift
//  nas-music
//
//  SYNO.API.Info / SYNO.API.Auth 的响应体。群晖所有接口都共享
//  { success, data, error: { code } } 这套外壳，所以只解出当前用到的字段。
//

import Foundation

struct SynologyErrorPayload: Decodable {
    let code: Int
}

struct SynologyAPIInfoResponse: Decodable {
    let success: Bool
    let data: [String: SynologyAPIInfoEntry]?
    let error: SynologyErrorPayload?
}

struct SynologyAPIInfoEntry: Decodable {
    let path: String
    let minVersion: Int
    let maxVersion: Int
}

struct SynologyLoginResponse: Decodable {
    let success: Bool
    let data: SynologyLoginData?
    let error: SynologyErrorPayload?
}

struct SynologyLoginData: Decodable {
    let sid: String
    let synotoken: String?
    let did: String?
}
