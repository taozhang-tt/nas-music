//
//  PlaybackManager.swift
//  nas-music
//
//  全局共享的播放状态，通过 @EnvironmentObject 注入到所有页面。
//  没有接入真实 AVPlayer/音频文件，用 Timer 模拟播放进度推进；play()/pause() 会驱动
//  AudioSessionManager 激活音频会话，让模拟播放在锁屏/后台时也能继续推进。
//

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

    private let audioSessionManager: AudioSessionManager
    private var timerCancellable: AnyCancellable?

    init(audioSessionManager: AudioSessionManager) {
        self.audioSessionManager = audioSessionManager
    }

    convenience init() {
        self.init(audioSessionManager: AudioSessionManager())
    }

    var currentSong: Song? {
        playlist.indices.contains(currentIndex) ? playlist[currentIndex] : nil
    }

    var duration: TimeInterval {
        currentSong?.duration ?? 0
    }

    var progress: Double {
        duration > 0 ? min(currentTime / duration, 1) : 0
    }

    /// 用给定的歌曲列表替换播放列表，并定位到 currentIndex；不会自动开始播放，
    /// 调用方需要紧接着调用 `play()`（这样 next()/previous() 才能在这组歌曲里循环）。
    func updatePlaylist(_ songs: [Song], currentIndex: Int) {
        playlist = songs
        self.currentIndex = songs.indices.contains(currentIndex) ? currentIndex : 0
        currentTime = 0
    }

    /// 播放指定歌曲：如果它已经在当前播放列表里，直接跳到对应位置（不打乱队列，给播放队列点歌用）；
    /// 否则把它设为单曲播放列表。
    func play(song: Song) {
        if let index = playlist.firstIndex(where: { $0.id == song.id }) {
            currentIndex = index
        } else {
            playlist = [song]
            currentIndex = 0
        }
        currentTime = 0
        play()
    }

    func play() {
        guard currentSong != nil else { return }
        isPlaying = true
        startTimer()
        audioSessionManager.resume()
    }

    func pause() {
        isPlaying = false
        stopTimer()
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
        currentTime = 0
    }

    func previous() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        currentTime = min(max(0, time), duration)
    }

    func toggleShuffle() {
        isShuffled.toggle()
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

    /// 每秒被 Timer 调用一次；去掉 `private` 是为了让单元测试可以直接调用它模拟时间流逝，
    /// 不必等待真实 Timer 触发。
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
        case .off, .all:
            next()
        }
    }
}
