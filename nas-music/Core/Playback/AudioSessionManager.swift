//
//  AudioSessionManager.swift
//  nas-music
//
//  配置 AVAudioSession 以支持真实 AVPlayer 播放、后台音频和锁屏控制。
//

import AVFoundation
import OSLog

@MainActor
final class AudioSessionManager {
    private static let logger = Logger(subsystem: "zero-tt.top.nas-music", category: "AudioSession")

    private let session = AVAudioSession.sharedInstance()
    private var isSessionActivated = false
    private var observers: [NSObjectProtocol] = []

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    init() {
        observeNotifications()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func prepareForPlayback() throws {
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isSessionActivated = true
            logCurrentConfiguration(prefix: "prepared")
        } catch {
            Self.logger.error("AVAudioSession 激活失败: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func suspend() {
        guard isSessionActivated else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActivated = false
            logCurrentConfiguration(prefix: "suspended")
        } catch {
            Self.logger.error("AVAudioSession 停用失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    func logCurrentConfiguration(prefix: String) {
        let route = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
        Self.logger.debug("AudioSession \(prefix, privacy: .public) category=\(self.session.category.rawValue, privacy: .public) mode=\(self.session.mode.rawValue, privacy: .public) otherAudio=\(self.session.isOtherAudioPlaying, privacy: .public) route=\(route, privacy: .public)")
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleInterruption(notification)
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleRouteChange(notification)
            }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            Self.logger.debug("AudioSession interruption began")
            onInterruptionBegan?()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            Self.logger.debug("AudioSession interruption ended shouldResume=\(shouldResume, privacy: .public)")
            onInterruptionEnded?(shouldResume)
        @unknown default:
            Self.logger.debug("AudioSession interruption unknown")
        }
        logCurrentConfiguration(prefix: "interruption")
    }

    private func handleRouteChange(_ notification: Notification) {
        let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        Self.logger.debug("AudioSession route changed reason=\(String(describing: reason), privacy: .public)")
        logCurrentConfiguration(prefix: "route")
    }
}
