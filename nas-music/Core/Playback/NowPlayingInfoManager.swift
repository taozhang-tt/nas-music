//
//  NowPlayingInfoManager.swift
//  nas-music
//
//  把 PlaybackManager 的状态镶镜到 MPNowPlayingInfoCenter，驱动锁屏和控制中心
//  展示的标题/歌手/专辑/进度信息。封面先用 AlbumArtView 的渐变占位图顶上（同步、立即可用），
//  有 coverId 时再异步换成 ArtworkImageLoader 加载到的真实封面；歌曲很快切换时靠
//  currentSong?.id 校验防止旧歌曲的封面晚到后覆盖新歌曲。
//

import Combine
import MediaPlayer
import SwiftUI

@MainActor
final class NowPlayingInfoManager {
    private let playbackManager: PlaybackManager
    private var cancellable: AnyCancellable?
    private var placeholderArtworkCache: [String: MPMediaItemArtwork] = [:]
    private var realArtworkCache: [String: MPMediaItemArtwork] = [:]
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkRequestedForSongID: String?

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
            artworkLoadTask?.cancel()
            artworkLoadTask = nil
            artworkRequestedForSongID = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyPlaybackDuration] = playbackManager.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackManager.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackManager.isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyArtwork] = artwork(for: song)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        loadRealArtworkIfNeeded(for: song)
    }

    /// 每首歌只会真正发起一次封面请求（用 artworkRequestedForSongID 去重，避免每次 tick
    /// 触发的 updateNowPlayingInfo 都重新请求）；加载失败时静默保留占位封面，不影响播放。
    private func loadRealArtworkIfNeeded(for song: Song) {
        guard realArtworkCache[song.id] == nil, artworkRequestedForSongID != song.id else { return }
        guard let coverId = song.coverId, !coverId.isEmpty else { return }
        artworkRequestedForSongID = song.id

        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in
            guard let self else { return }
            guard let image = try? await ArtworkImageLoader.shared.loadImage(coverId: coverId, size: .large) else {
                return
            }
            guard !Task.isCancelled, self.playbackManager.currentSong?.id == song.id else { return }
            self.realArtworkCache[song.id] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlayingInfo()
        }
    }

    private func artwork(for song: Song) -> MPMediaItemArtwork {
        if let real = realArtworkCache[song.id] {
            return real
        }
        if let cached = placeholderArtworkCache[song.id] {
            return cached
        }

        let renderer = ImageRenderer(content: AlbumArtView(id: song.id)
            .frame(width: 300, height: 300))
        let image = renderer.uiImage ?? UIImage(systemName: "music.note") ?? UIImage()
        let mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        placeholderArtworkCache[song.id] = mediaArtwork
        return mediaArtwork
    }
}
