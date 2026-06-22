//
//  PlaybackManager.swift
//  nas-music
//
//  全局共享的播放状态，通过 @EnvironmentObject 注入到所有页面。播放前动态换取或选择
//  一个真实音频 URL，然后统一交给 AVPlayer。isPlaying 只来自 AVPlayer.timeControlStatus，
//  不由按钮点击手动伪造。
//

import AVFoundation
import Combine
import Foundation
import OSLog

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
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var waitingReasonText: String?

    private static let logger = Logger(subsystem: "zero-tt.top.nas-music", category: "Playback")
    private static let publicRemoteTestURL = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!

    private let audioSessionManager: AudioSessionManager
    private var musicLibraryProvider: MusicLibraryProvider

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endOfItemCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var streamFetchTask: Task<Void, Never>?
    private var streamDuration: TimeInterval?
    private var preparedSongID: String?
    private var shouldResumeAfterInterruption = false
    private var lastDiagnosticSecond: Int = -1

    init(audioSessionManager: AudioSessionManager, musicLibraryProvider: MusicLibraryProvider) {
        self.audioSessionManager = audioSessionManager
        self.musicLibraryProvider = musicLibraryProvider
        audioSessionManager.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.shouldResumeAfterInterruption = self.isPlaying
            self.player?.pause()
        }
        audioSessionManager.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, shouldResume, self.shouldResumeAfterInterruption else { return }
            self.play()
        }
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
        duration > 0 && currentTime.isFinite ? min(currentTime / duration, 1) : 0
    }

    var statusText: String? {
        switch playbackState {
        case .loading:
            return "正在准备音频"
        case .buffering:
            return waitingReasonText ?? "正在缓冲"
        case .failed(let message):
            return message
        case .idle, .playing, .paused:
            return nil
        }
    }

    func updatePlaylist(_ songs: [Song], currentIndex: Int) {
        resetEngine()
        playlist = songs
        self.currentIndex = songs.indices.contains(currentIndex) ? currentIndex : 0
    }

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
        if preparedSongID == song.id, player != nil {
            resumeEngine()
        } else {
            loadAndPlayCurrentSong()
        }
    }

    func pause() {
        player?.pause()
        audioSessionManager.suspend()
        updateStateFromPlayer()
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
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func toggleShuffle() {
        isShuffled.toggle()
    }

    func dismissPlaybackError() {
        if case .failed = playbackState {
            setPlaybackState(.paused)
        }
    }

    func retryCurrentSong() {
        guard currentSong != nil else { return }
        loadAndPlayCurrentSong()
    }

    func playLocalTestAudio() {
        guard let url = Self.localTestAudioURL() else {
            setFailure("找不到 Bundle 内的本地测试音频。")
            return
        }
        let song = Song(
            id: "debug-local-test-audio",
            title: "本地测试音频",
            artist: "Debug",
            album: "Playback Diagnostics",
            duration: 3,
            source: .local(fileURL: url.absoluteString)
        )
        resetEngine()
        playlist = [song]
        currentIndex = 0
        preparedSongID = song.id
        beginPlayback(resource: PlaybackStreamResource(url: url), song: song, shouldProbeStream: false)
    }

    func playPublicRemoteTestAudio() {
        let song = Song(
            id: "debug-public-remote-test-audio",
            title: "公开远程测试音频",
            artist: "SoundHelix",
            album: "Playback Diagnostics",
            duration: nil,
            source: .local(fileURL: Self.publicRemoteTestURL.absoluteString)
        )
        resetEngine()
        playlist = [song]
        currentIndex = 0
        preparedSongID = song.id
        setPlaybackState(.loading)
        streamFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.probeThenBeginPlayback(resource: PlaybackStreamResource(url: Self.publicRemoteTestURL), song: song)
        }
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
        waitingReasonText = nil
        currentTime = 0
        streamDuration = nil
        preparedSongID = song.id
        setPlaybackState(.loading)

        if case .mock = song.source {
            guard let url = Self.localTestAudioURL() else {
                setFailure("Mock 歌曲需要 Bundle 本地测试音频，但文件不存在。")
                return
            }
            beginPlayback(resource: PlaybackStreamResource(url: url), song: song, shouldProbeStream: false)
            return
        }

        let provider = musicLibraryProvider
        streamFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resource = try await provider.fetchStreamResource(for: song)
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                await self.probeThenBeginPlayback(resource: resource, song: song)
            } catch {
                guard !Task.isCancelled, self.currentSong?.id == song.id else { return }
                self.preparedSongID = nil
                self.setFailure((error as? LocalizedError)?.errorDescription ?? "无法获取播放地址，请稍后重试。")
            }
        }
    }

    private func probeThenBeginPlayback(resource: PlaybackStreamResource, song: Song) async {
        do {
            let probe = try await probeStreamURL(resource.url, headers: resource.headers)
            Self.logger.debug("stream probe ok url=\(Self.redactedURLDescription(resource.url), privacy: .public) status=\(probe.statusCode, privacy: .public) contentType=\(probe.contentType ?? "nil", privacy: .public) contentLength=\(probe.contentLengthText, privacy: .public) headers=\(!resource.headers.isEmpty, privacy: .public)")
            guard !Task.isCancelled, currentSong?.id == song.id else { return }
            beginPlayback(resource: resource, song: song, shouldProbeStream: false)
        } catch {
            guard !Task.isCancelled, currentSong?.id == song.id else { return }
            setFailure("音频流不可播放：\(error.localizedDescription)")
        }
    }

    private func beginPlayback(resource: PlaybackStreamResource, song: Song, shouldProbeStream: Bool = true) {
        guard !shouldProbeStream else {
            streamFetchTask = Task { [weak self] in
                guard let self else { return }
                await self.probeThenBeginPlayback(resource: resource, song: song)
            }
            return
        }

        do {
            try audioSessionManager.prepareForPlayback()
        } catch {
            setFailure("AudioSession 配置失败：\(error.localizedDescription)")
            return
        }

        teardownPlayer()
        let asset = Self.playerAsset(url: resource.url, song: song, headers: resource.headers)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = 1
        player.isMuted = false

        self.player = player
        observePlayer(player, item: item)
        observeEndOfPlayback(for: item)
        observeDuration(of: item)
        addTimeObserver(to: player)
        logPlaybackDiagnostics(context: "before play")
        player.play()
        updateStateFromPlayer()
    }

    private func resumeEngine() {
        playbackError = nil
        waitingReasonText = nil
        do {
            try audioSessionManager.prepareForPlayback()
        } catch {
            setFailure("AudioSession 配置失败：\(error.localizedDescription)")
            return
        }
        player?.play()
        updateStateFromPlayer()
    }

    private func resetEngine() {
        streamFetchTask?.cancel()
        streamFetchTask = nil
        teardownPlayer()
        preparedSongID = nil
        currentTime = 0
        streamDuration = nil
        waitingReasonText = nil
        lastDiagnosticSecond = -1
        setPlaybackState(.idle)
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
        cancellables.removeAll()
    }

    private func observePlayer(_ player: AVPlayer, item: AVPlayerItem) {
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] _ in
                self?.updateStateFromPlayer()
                self?.logPlaybackDiagnostics(context: "timeControlStatus changed")
            }
            .store(in: &cancellables)

        player.publisher(for: \.reasonForWaitingToPlay)
            .sink { [weak self] _ in
                self?.updateStateFromPlayer()
            }
            .store(in: &cancellables)

        item.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .failed {
                    self.setFailure("播放失败：\(item.error?.localizedDescription ?? "AVPlayerItem 加载失败")")
                }
                self.logPlaybackDiagnostics(context: "item status changed")
            }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] _ in self?.logPlaybackDiagnostics(context: "keepUp changed") }
            .store(in: &cancellables)

        item.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] _ in self?.logPlaybackDiagnostics(context: "buffer changed") }
            .store(in: &cancellables)
    }

    private func updateStateFromPlayer() {
        guard let player else {
            isPlaying = false
            isLoadingStream = playbackState == .loading
            return
        }

        isPlaying = player.timeControlStatus == .playing
        waitingReasonText = player.reasonForWaitingToPlay.map(Self.waitingReasonDescription)

        if case .failed = playbackState {
            isLoadingStream = false
            return
        }

        switch player.timeControlStatus {
        case .playing:
            setPlaybackState(.playing)
        case .paused:
            setPlaybackState(.paused)
        case .waitingToPlayAtSpecifiedRate:
            setPlaybackState(.buffering)
        @unknown default:
            setPlaybackState(.buffering)
        }
    }

    private func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
        playbackError = state.errorMessage
        isLoadingStream = state == .loading
        if state != .playing {
            isPlaying = false
        }
    }

    private func setFailure(_ message: String) {
        Self.logger.error("playback failed: \(message, privacy: .public)")
        teardownPlayer()
        preparedSongID = nil
        setPlaybackState(.failed(message: message))
        audioSessionManager.logCurrentConfiguration(prefix: "failure")
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                    self.logPeriodicDiagnosticsIfNeeded(second: Int(seconds.rounded(.down)))
                }
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
        let message = player?.currentItem?.error?.localizedDescription ?? "播放失败，请稍后重试。"
        setFailure(message)
    }

    /// 保留给单元测试直接推进旧模拟进度；真实播放进度来自 AVPlayer time observer。
    func tick() {
        guard isPlaying, player == nil else { return }
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

    // MARK: - 诊断

    private func logPeriodicDiagnosticsIfNeeded(second: Int) {
        guard second != lastDiagnosticSecond else { return }
        lastDiagnosticSecond = second
        if second <= 5 || second % 10 == 0 {
            logPlaybackDiagnostics(context: "time tick")
        }
    }

    private func logPlaybackDiagnostics(context: String) {
        guard let player else {
            Self.logger.debug("[\(context, privacy: .public)] player=nil")
            audioSessionManager.logCurrentConfiguration(prefix: context)
            return
        }
        let item = player.currentItem
        let duration = Self.timeDescription(item?.duration)
        let loadedRanges = item?.loadedTimeRanges.map { value in
            let range = value.timeRangeValue
            return "\(Self.timeDescription(range.start))+\(Self.timeDescription(range.duration))"
        }.joined(separator: ",") ?? "nil"
        let accessEvents = item?.accessLog()?.events ?? []
        let errorEvents = item?.errorLog()?.events ?? []
        let lastAccess = accessEvents.last
        let lastError = errorEvents.last

        Self.logger.debug("""
        [\(context, privacy: .public)] timeControlStatus=\(Self.timeControlStatusDescription(player.timeControlStatus), privacy: .public) reason=\(Self.waitingReasonDescription(player.reasonForWaitingToPlay), privacy: .public) itemStatus=\(Self.itemStatusDescription(item?.status), privacy: .public) itemError=\(item?.error?.localizedDescription ?? "nil", privacy: .public) duration=\(duration, privacy: .public) loaded=\(loadedRanges, privacy: .public) keepUp=\(item?.isPlaybackLikelyToKeepUp ?? false, privacy: .public) bufferEmpty=\(item?.isPlaybackBufferEmpty ?? false, privacy: .public) errorLogEvents=\(errorEvents.count, privacy: .public) lastErrorStatus=\(lastError?.errorStatusCode ?? 0, privacy: .public) lastErrorDomain=\(lastError?.errorDomain ?? "nil", privacy: .public) accessLogEvents=\(accessEvents.count, privacy: .public) observedBitrate=\(lastAccess?.observedBitrate ?? 0, privacy: .public) indicatedBitrate=\(lastAccess?.indicatedBitrate ?? 0, privacy: .public) currentTime=\(self.currentTime, privacy: .public) volume=\(player.volume, privacy: .public) muted=\(player.isMuted, privacy: .public)
        """)
        audioSessionManager.logCurrentConfiguration(prefix: context)
    }

    private static func timeControlStatusDescription(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: "paused"
        case .waitingToPlayAtSpecifiedRate: "waitingToPlayAtSpecifiedRate"
        case .playing: "playing"
        @unknown default: "unknown"
        }
    }

    private static func itemStatusDescription(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .none: "nil"
        case .some(.unknown): "unknown"
        case .some(.readyToPlay): "readyToPlay"
        case .some(.failed): "failed"
        @unknown default: "unknown"
        }
    }

    private static func waitingReasonDescription(_ reason: AVPlayer.WaitingReason?) -> String {
        guard let reason else { return "nil" }
        switch reason {
        case .evaluatingBufferingRate:
            return "evaluatingBufferingRate"
        case .toMinimizeStalls:
            return "toMinimizeStalls"
        case .noItemToPlay:
            return "noItemToPlay"
        default:
            return reason.rawValue
        }
    }

    private static func timeDescription(_ time: CMTime?) -> String {
        guard let time else { return "nil" }
        let seconds = time.seconds
        return seconds.isFinite ? String(format: "%.2f", seconds) : "indefinite"
    }

    private static func localTestAudioURL() -> URL? {
        Bundle.main.url(forResource: "LocalPlaybackTest", withExtension: "wav")
    }

    private static func playerAsset(url: URL, song: Song, headers: [String: String]) -> AVURLAsset {
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        guard let mimeType = overrideMIMEType(for: song) else {
            return AVURLAsset(url: url, options: options.isEmpty ? nil : options)
        }
        options[AVURLAssetOverrideMIMETypeKey] = mimeType
        return AVURLAsset(url: url, options: options)
    }

    private static func overrideMIMEType(for song: Song) -> String? {
        guard case .synology = song.source else { return nil }
        switch song.fileExtension?.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "wav":
            return "audio/wav"
        case "ogg", "oga":
            return "audio/ogg"
        default:
            return nil
        }
    }

    private static func redactedURLDescription(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let hasAuth = items.contains { item in
            let name = item.name.lowercased()
            return name == "_sid" || name == "sid" || name == "synotoken" || name == "token" || name == "passwd" || name == "password"
        }
        components?.query = nil
        let scheme = components?.scheme ?? url.scheme ?? "unknown"
        let host = components?.host ?? url.host ?? "nil"
        let path = components?.path ?? url.path
        return "\(scheme)://\(host)\(path) authQuery=\(hasAuth)"
    }

    // MARK: - Stream probe

    private struct StreamProbeResult {
        let statusCode: Int
        let contentType: String?
        let contentLength: Int64?

        var contentLengthText: String {
            contentLength.map(String.init) ?? "nil"
        }
    }

    private func probeStreamURL(_ url: URL, headers: [String: String]) async throws -> StreamProbeResult {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return StreamProbeResult(statusCode: 0, contentType: "file", contentLength: nil)
        }

        Self.logger.debug("stream probe start url=\(Self.redactedURLDescription(url), privacy: .public)")
        do {
            let head = try await performStreamProbe(url: url, method: "HEAD", headers: headers)
            if Self.requiresBodyProbe(contentType: head.contentType) {
                Self.logger.debug("stream HEAD content type requires body probe contentType=\(head.contentType ?? "nil", privacy: .public)")
                return try await performStreamProbe(url: url, method: "GET", headers: headers)
            }
            return head
        } catch {
            Self.logger.debug("stream HEAD probe failed url=\(Self.redactedURLDescription(url), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return try await performStreamProbe(url: url, method: "GET", headers: headers)
        }
    }

    private func performStreamProbe(url: URL, method: String, headers: [String: String]) async throws -> StreamProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if method == "GET" {
            request.setValue("bytes=0-63", forHTTPHeaderField: "Range")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "PlaybackStreamProbe", code: -1, userInfo: [NSLocalizedDescriptionKey: "没有收到 HTTP 响应"])
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        let contentLengthText = http.value(forHTTPHeaderField: "Content-Length")
        let contentLength = contentLengthText.flatMap(Int64.init)
        let result = StreamProbeResult(statusCode: http.statusCode, contentType: contentType, contentLength: contentLength)
        try validateProbeResult(result, url: url)
        if method == "GET" {
            try validateProbeBody(data, contentType: contentType)
        }
        return result
    }

    private func validateProbeResult(_ result: StreamProbeResult, url: URL) throws {
        guard (200..<300).contains(result.statusCode) else {
            let hint: String
            switch result.statusCode {
            case 401, 403:
                hint = "HTTP \(result.statusCode)，sid/权限/鉴权可能失效。"
            case 404:
                hint = "HTTP 404，stream URL 构造可能不正确。"
            default:
                hint = "HTTP \(result.statusCode)。"
            }
            throw NSError(domain: "PlaybackStreamProbe", code: result.statusCode, userInfo: [NSLocalizedDescriptionKey: hint])
        }

        let contentType = result.contentType?.lowercased() ?? ""
        if contentType.contains("json") {
            throw NSError(domain: "PlaybackStreamProbe", code: result.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器返回 JSON，不是音频流。"])
        }

        if url.scheme?.lowercased() == "http" {
            Self.logger.debug("stream uses HTTP url=\(Self.redactedURLDescription(url), privacy: .public); check ATS if playback fails")
        }
    }

    private static func requiresBodyProbe(contentType: String?) -> Bool {
        let contentType = contentType?.lowercased() ?? ""
        guard !contentType.isEmpty else { return true }
        return contentType.contains("text/") || contentType.contains("json") || contentType.contains("xml")
    }

    private func validateProbeBody(_ data: Data, contentType: String?) throws {
        let prefix = data.prefix(64)
        guard let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let first = text.first else { return }
        if first == "{" || first == "[" {
            throw NSError(domain: "PlaybackStreamProbe", code: -2, userInfo: [NSLocalizedDescriptionKey: Self.jsonProbeErrorMessage(from: data)])
        }
        if Self.looksLikeAudio(data) {
            return
        }
        if Self.requiresBodyProbe(contentType: contentType), Self.looksLikePrintableText(prefix) {
            throw NSError(domain: "PlaybackStreamProbe", code: -3, userInfo: [NSLocalizedDescriptionKey: "服务器返回文本，不是音频流。prefix=\(Self.safeTextPrefix(from: prefix))"])
        }
    }

    private static func looksLikeAudio(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(16))
        guard bytes.count >= 2 else { return false }
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return true } // ID3
        if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 { return true } // MPEG frame
        if bytes.count >= 4, bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 { return true } // fLaC
        if bytes.count >= 4, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 { return true } // RIFF/WAV
        if bytes.count >= 12, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return true } // MP4/M4A
        if bytes.count >= 4, bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53 { return true } // OggS
        return false
    }

    private static func looksLikePrintableText(_ data: Data.SubSequence) -> Bool {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return false }
        let printableCount = bytes.filter { byte in
            byte == 0x09 || byte == 0x0A || byte == 0x0D || (0x20...0x7E).contains(byte)
        }.count
        return Double(printableCount) / Double(bytes.count) > 0.85
    }

    private static func safeTextPrefix(from data: Data.SubSequence) -> String {
        let text = String(data: Data(data), encoding: .utf8) ?? ""
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(cleaned.prefix(48))
    }

    private static func jsonProbeErrorMessage(from data: Data) -> String {
        struct ProbeAPIError: Decodable {
            let code: Int?
        }
        struct ProbeAPIResponse: Decodable {
            let success: Bool?
            let error: ProbeAPIError?
        }

        guard let response = try? JSONDecoder().decode(ProbeAPIResponse.self, from: data) else {
            return "服务器返回 JSON，不是音频流。"
        }

        if let code = response.error?.code {
            return "服务器返回 JSON，不是音频流。Synology errorCode=\(code)。"
        }
        if let success = response.success {
            return "服务器返回 JSON，不是音频流。success=\(success)。"
        }
        return "服务器返回 JSON，不是音频流。"
    }
}
