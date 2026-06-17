//
//  PlaybackManager.swift
//  nas-music
//
//  全局共享的播放状态，通过 @EnvironmentObject 注入到所有页面。播放分两条腿：
//  .mock 来源的歌曲没有真实音频文件，继续用 Timer 模拟进度推进；.synology/.local 来源的
//  歌曲在播放前通过 musicLibraryProvider.fetchStreamURL(for:) 动态换取 stream URL，
//  再用真正的 AVPlayer 播放。两条腿共用同一套 playlist/currentIndex/isPlaying/currentTime
//  等可观察状态和 next()/previous()/seek()/repeatMode 逻辑，调用方（UI）不需要关心当前
//  播放的是哪一种来源。
//

import AVFoundation
import Foundation
import Combine

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var playlist: [Song] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var isLoadingStream: Bool = false
    @Published private(set) var playbackError: String?

    private let audioSessionManager: AudioSessionManager
    private var musicLibraryProvider: MusicLibraryProvider

    private var timerCancellable: AnyCancellable?
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endOfItemCancellable: AnyCancellable?
    private var streamFetchTask: Task<Void, Never>?
    private var streamDuration: TimeInterval?
    /// 当前已经准备好播放引擎（Timer 或 AVPlayer）的歌曲 id；play() 用它判断是「续播」还是
    /// 「重新加载」。
    private var preparedSongID: String?

    init(audioSessionManager: AudioSessionManager, musicLibraryProvider: MusicLibraryProvider) {
        self.audioSessionManager = audioSessionManager
        self.musicLibraryProvider = musicLibraryProvider
    }

    convenience init(musicLibraryProvider: MusicLibraryProvider = MockMusicLibraryProvider()) {
        self.init(audioSessionManager: AudioSessionManager(), musicLibraryProvider: musicLibraryProvider)
    }

    /// NAS 连接状态变化时，切换歌曲播放该用哪个 Provider 解析 stream URL。
    func updateMusicLibraryProvider(_ provider: MusicLibraryProvider) {
        musicLibraryProvider = provider
    }

    var currentSong: Song? {
        playlist.indices.contains(currentIndex) ? playlist[currentIndex] : nil
    }

    var duration: TimeInterval {
        streamDuration ?? currentSong?.duration ?? 0
    }

    var progress: Double {
        duration > 0 ? min(currentTime / duration, 1) : 0
    }

    /// 用给定的歌曲列表替换播放列表，并定位到 currentIndex；不会自动开始播放，
    /// 调用方需要紧接着调用 `play()`（这样 next()/previous() 才能在这组歌曲里循环）。
    func updatePlaylist(_ songs: [Song], currentIndex: Int) {
        resetEngine()
        playlist = songs
        self.currentIndex = songs.indices.contains(currentIndex) ? currentIndex : 0
    }

    /// 播放指定歌曲：如果它已经在当前播放列表里，直接跳到对应位置（不打乱队列，给播放队列点歌用）；
    /// 否则把它设为单曲播放列表。
    func play(song: Song) {
        resetEngine()
        if let index = playlist.firstIndex(where: { $0.id == song.id }) {
            currentIndex = index
        } else {
            playlist = [song]
            currentIndex = 0
        }
        loadAndPlayCurrentSong()
    }

    func play() {
        guard let song = currentSong else { return }
        if preparedSongID == song.id {
            resumeEngine(for: song)
        } else {
            loadAndPlayCurrentSong()
        }
    }

    func pause() {
        isPlaying = false
        stopTimer()
        player?.pause()
        audioSessionManager.suspend()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func next() {
        guard !playlist.isEmpty else { return }
        if isShuffled, playlist.count > 1 {
            var randomIndex = Int.random(in: 0..<playlist.count)
            while randomIndex == currentIndex {
                randomIndex = Int.random(in: 0..<playlist.count)
            }
            currentIndex = randomIndex
        } else {
            currentIndex = (currentIndex + 1) % playlist.count
        }
        advanceToCurrentSongPreservingPlayState()
    }

    func previous() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        advanceToCurrentSongPreservingPlayState()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        currentTime = clamped
        if let player {
            player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
    }

    func dismissPlaybackError() {
        playbackError = nil
    }

    // MARK: - 播放引擎

    private func advanceToCurrentSongPreservingPlayState() {
        let wasPlaying = isPlaying
        resetEngine()
        if wasPlaying {
            loadAndPlayCurrentSong()
        }
    }

    private func loadAndPlayCurrentSong() {
        guard let song = currentSong else { return }
        streamFetchTask?.cancel()
        playbackError = nil
        currentTime = 0
        streamDuration = nil
        preparedSongID = song.id
        isLoadingStream = true

        let provider = musicLibraryProvider
        streamFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await provider.fetchStreamURL(for: song)
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                self.beginPlayback(url: url, song: song)
            } catch {
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                self.isLoadingStream = false
                self.preparedSongID = nil
                self.playbackError = (error as? LocalizedError)?.errorDescription ?? "无法获取播放地址，请稍后重试。"
            }
        }
    }

    private func beginPlayback(url: URL, song: Song) {
        isLoadingStream = false
        switch song.source {
        case .mock:
            isPlaying = true
            startTimer()
            audioSessionManager.resume()
        case .synology, .local:
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            observeEndOfPlayback(for: item)
            observeDuration(of: item)
            addTimeObserver(to: player)
            player.play()
            isPlaying = true
            audioSessionManager.resume()
        }
    }

    private func resumeEngine(for song: Song) {
        playbackError = nil
        isPlaying = true
        switch song.source {
        case .mock:
            startTimer()
        case .synology, .local:
            player?.play()
        }
        audioSessionManager.resume()
    }

    private func resetEngine() {
        streamFetchTask?.cancel()
        streamFetchTask = nil
        stopTimer()
        teardownPlayer()
        preparedSongID = nil
        isLoadingStream = false
        isPlaying = false
        playbackError = nil
        currentTime = 0
        streamDuration = nil
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player?.pause()
        player = nil
        endOfItemCancellable?.cancel()
        endOfItemCancellable = nil
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // addPeriodicTimeObserver 的 queue 是 .main，这里断言隔离是安全的。
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
    }

    private func observeDuration(of item: AVPlayerItem) {
        Task { [weak self] in
            guard let seconds = try? await item.asset.load(.duration).seconds, seconds.isFinite, seconds > 0 else { return }
            guard let self, self.player?.currentItem === item else { return }
            self.streamDuration = seconds
        }
    }

    private func observeEndOfPlayback(for item: AVPlayerItem) {
        let didFinish = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .map { _ in true }
        let didFail = NotificationCenter.default
            .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .map { _ in false }

        endOfItemCancellable = didFinish.merge(with: didFail)
            .sink { [weak self] finishedSuccessfully in
                if finishedSuccessfully {
                    self?.handleTrackFinished()
                } else {
                    self?.handlePlaybackFailure()
                }
            }
    }

    private func handlePlaybackFailure() {
        resetEngine()
        playbackError = "播放失败，请稍后重试。"
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// 每秒被 Timer 调用一次（仅 .mock 来源使用）；去掉 `private` 是为了让单元测试可以直接
    /// 调用它模拟时间流逝，不必等待真实 Timer 触发。
    func tick() {
        guard isPlaying else { return }
        currentTime += 1
        if currentTime >= duration {
            handleTrackFinished()
        }
    }

    private func handleTrackFinished() {
        switch repeatMode {
        case .one:
            currentTime = 0
            if let player {
                player.seek(to: .zero)
                player.play()
            }
        case .off, .all:
            next()
        }
    }
}
