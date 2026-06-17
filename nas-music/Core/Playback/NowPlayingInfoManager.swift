//
//  NowPlayingInfoManager.swift
//  nas-music
//
//  把 PlaybackManager 的状态镶镜到 MPNowPlayingInfoCenter，驱动锁屏和控制中心
//  展示的标题/歌手/专辑/进度信息。没有真实封面时复用 AlbumArtView 的渐变占位封面
//  渲染成 UIImage。
//

import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class NowPlayingInfoManager {
    private let playbackManager: PlaybackManager
    private var cancellable: AnyCancellable?
    private var artworkCache: [UUID: MPMediaItemArtwork] = [:]

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        cancellable = playbackManager.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange 在属性真正变化之前触发，派发到下一个 runloop
                // 再读取，确保读到的是变化之后的最新值。
                DispatchQueue.main.async {
                    self?.updateNowPlayingInfo()
                }
            }
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let song = playbackManager.currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyPlaybackDuration] = song.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackManager.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackManager.isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyArtwork] = artwork(for: song)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artwork(for song: Song) -> MPMediaItemArtwork {
        if let cached = artworkCache[song.id] {
            return cached
        }

        let renderer = ImageRenderer(content: AlbumArtView(id: song.id.uuidString)
            .frame(width: 300, height: 300))
        let image = renderer.uiImage ?? UIImage(systemName: "music.note") ?? UIImage()
        let mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkCache[song.id] = mediaArtwork
        return mediaArtwork
    }
}
