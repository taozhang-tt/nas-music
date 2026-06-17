//
//  MusicLibraryViewState.swift
//  nas-music
//
//  音乐库相关页面（首页/音乐库/专辑详情）统一使用的加载状态。
//

import Foundation

enum MusicLibraryViewState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}
