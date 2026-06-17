//
//  AudioSessionManager.swift
//  nas-music
//
//  配置 AVAudioSession 以支持后台播放/锁屏控制。当前播放内核仍是 PlaybackManager
//  里的 Timer 模拟进度（没有真实音频流），但 iOS 只在音频会话“真正渲染音频”时才会
//  豁免后台挂起；因此这里额外跑一个静音的 AVAudioEngine 循环，让 App 在切到后台后
//  仍被系统视为“正在播放音频”，从而保证 Timer 和 Now Playing 信息能继续推进。等接入
//  真实音频流后，这个静音引擎可以被真实的解码输出取代。
//

import AVFoundation
import OSLog

@MainActor
final class AudioSessionManager {
    private static let logger = Logger(subsystem: "zero-tt.top.nas-music", category: "AudioSession")

    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var isSessionActivated = false
    private var isEngineConfigured = false

    func resume() {
        activateSessionIfNeeded()
        configureEngineIfNeeded()

        guard !engine.isRunning else { return }
        do {
            try engine.start()
            playerNode.play()
        } catch {
            Self.logger.error("启动静音播放引擎失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func suspend() {
        guard engine.isRunning else { return }
        playerNode.pause()
        engine.pause()
    }

    private func activateSessionIfNeeded() {
        guard !isSessionActivated else { return }
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isSessionActivated = true
        } catch {
            Self.logger.error("AVAudioSession 激活失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 用一段全零的 PCM buffer 循环播放来产生“静音音频”，详见文件头注释。
    private func configureEngineIfNeeded() {
        guard !isEngineConfigured else { return }
        isEngineConfigured = true

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0

        let frameCount = AVAudioFrameCount(format.sampleRate * 0.5)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                memset(channelData[channel], 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        engine.prepare()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
    }
}
