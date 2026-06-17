//
//  RemoteCommandManager.swift
//  nas-music
//
//  把锁屏/控制中心的远程播放指令转发给 PlaybackManager。只支持 play/pause/
//  toggle/next/previous/seek 这 6 个指令，其余指令显式禁用，避免系统展示
//  无法响应的按钮。
//

import MediaPlayer

@MainActor
final class RemoteCommandManager {
    private let playbackManager: PlaybackManager
    private var isConfigured = false

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        configureCommandsIfNeeded()
    }

    private func configureCommandsIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.playbackManager.play()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.playbackManager.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.playbackManager.toggle()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.playbackManager.next()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.playbackManager.previous()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.playbackManager.seek(to: event.positionTime)
            return .success
        }

        disableUnsupportedCommands(center)
    }

    private func disableUnsupportedCommands(_ center: MPRemoteCommandCenter) {
        let unsupported = [
            center.skipForwardCommand,
            center.skipBackwardCommand,
            center.seekForwardCommand,
            center.seekBackwardCommand,
            center.changeRepeatModeCommand,
            center.changeShuffleModeCommand,
            center.ratingCommand,
            center.likeCommand,
            center.dislikeCommand,
            center.bookmarkCommand,
            center.enableLanguageOptionCommand,
            center.disableLanguageOptionCommand,
        ]
        unsupported.forEach { $0.isEnabled = false }
    }
}
