//
//  PlaybackManager.swift
//  nas-music
//
//  模拟播放器传输状态（队列、进度、播放/暂停、随机、循环）。
//  没有接入真实 AVPlayer/音频文件，用 Timer 模拟进度推进。
//

import Foundation
import Combine

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    private var timerCancellable: AnyCancellable?

    var currentSong: Song? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var duration: TimeInterval {
        currentSong?.duration ?? 0
    }

    var progress: Double {
        duration > 0 ? min(currentTime / duration, 1) : 0
    }

    func play(songs: [Song], startAt index: Int = 0) {
        guard songs.indices.contains(index) else { return }
        queue = songs
        currentIndex = index
        currentTime = 0
        isPlaying = true
        startTimer()
    }

    func playSong(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentTime = 0
        isPlaying = true
        startTimer()
    }

    func playPause() {
        guard currentSong != nil else { return }
        isPlaying.toggle()
        isPlaying ? startTimer() : stopTimer()
    }

    func skipToNext() {
        advance(by: 1)
    }

    func skipToPrevious() {
        if currentTime > 3 {
            currentTime = 0
            return
        }
        advance(by: -1)
    }

    func seek(to time: TimeInterval) {
        currentTime = min(max(0, time), duration)
    }

    func toggleShuffle() {
        isShuffled.toggle()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
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

    private func tick() {
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
            advance(by: 1)
        }
    }

    private func advance(by delta: Int) {
        guard !queue.isEmpty else { return }
        let nextIndex = currentIndex + delta
        if queue.indices.contains(nextIndex) {
            currentIndex = nextIndex
            currentTime = 0
        } else if repeatMode == .all {
            currentIndex = delta > 0 ? 0 : queue.count - 1
            currentTime = 0
        } else {
            currentTime = duration
            isPlaying = false
            stopTimer()
        }
    }
}
