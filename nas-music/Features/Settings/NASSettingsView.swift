//
//  NASSettingsView.swift
//  nas-music
//

import SwiftUI

struct NASSettingsView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager
    @ObservedObject private var syncService: MusicLibrarySyncService
    @StateObject private var viewModel: NASSettingsViewModel

    @AppStorage("nas.settings.allowHTTPLANTesting") private var allowHTTPLANTesting = false
    @AppStorage("nas.settings.showDiagnostics") private var showDiagnostics = false

    @State private var showDeleteConfirmation = false
    @State private var showClearCredentialConfirmation = false
    @State private var showRebuildIndexConfirmation = false
    @State private var showClearIndexConfirmation = false

    init(sessionManager: NASSessionManager, syncService: MusicLibrarySyncService) {
        self.syncService = syncService
        _viewModel = StateObject(wrappedValue: NASSettingsViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        Form {
            statusSection
            formSection
            actionsSection
            playbackDebugSection
            musicLibrarySection
            advancedSection
            cacheManagementSection
        }
        .navigationTitle("NAS 设置")
        .disabled(viewModel.isBusy)
        .task {
            await viewModel.loadArtworkCacheStats()
            await syncService.refreshLocalStats()
        }
    }

    private var statusSection: some View {
        Section("连接状态") {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusTitle)
                        .font(.body.weight(.medium))
                    if let failureDetail = viewModel.failureDetail {
                        Text(failureDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.isBusy {
                    ProgressView()
                }
            }

            if let testResultMessage = viewModel.testResultMessage {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        case .failed: .red
        }
    }

    private var formSection: some View {
        Section("NAS 地址") {
            TextField("连接名称", text: $viewModel.name)
                .textInputAutocapitalization(.never)
            TextField("主机地址（如 192.168.1.10）", text: $viewModel.host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("端口", text: $viewModel.port)
                .keyboardType(.numberPad)
            Toggle("使用 HTTPS", isOn: $viewModel.useHTTPS)
                .disabled(!allowHTTPLANTesting)
                .onChange(of: allowHTTPLANTesting) { _, isAllowed in
                    if !isAllowed { viewModel.useHTTPS = true }
                }
            TextField("用户名", text: $viewModel.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("密码", text: $viewModel.password)
        }
    }

    private var actionsSection: some View {
        Section("操作") {
            Button("测试连接") {
                viewModel.testConnection()
            }
            .disabled(viewModel.isBusy)

            Button("保存并连接") {
                viewModel.saveAndConnect()
            }
            .disabled(viewModel.isBusy)

            Button("断开连接") {
                viewModel.disconnect()
            }
            .disabled(viewModel.isBusy || viewModel.state != .connected)

            Button("删除配置", role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(viewModel.isBusy || !viewModel.hasSavedConfig)
            .confirmationDialog(
                "确定要删除这个 NAS 连接配置吗？",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除配置", role: .destructive) {
                    viewModel.deleteConfig()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("保存的地址、用户名和登录凭证都会被清除。")
            }
        }
    }

    private var advancedSection: some View {
        Section("高级选项") {
            Toggle("允许 HTTP 局域网测试", isOn: $allowHTTPLANTesting)
            Toggle("显示诊断信息", isOn: $showDiagnostics)

            if showDiagnostics {
                Text(viewModel.diagnosticsText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("清除登录凭证", role: .destructive) {
                showClearCredentialConfirmation = true
            }
            .disabled(viewModel.isBusy || !viewModel.hasStoredCredential)
            .confirmationDialog(
                "确定要清除已保存的登录凭证吗？",
                isPresented: $showClearCredentialConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除登录凭证", role: .destructive) {
                    viewModel.clearCredentials()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("地址和用户名会保留，下次需要重新输入密码登录。")
            }
        }
    }

    private var playbackDebugSection: some View {
        Section("播放诊断") {
            Button {
                playbackManager.playLocalTestAudio()
            } label: {
                Label("播放本地测试音频", systemImage: "speaker.wave.2.fill")
            }

            Button {
                playbackManager.playPublicRemoteTestAudio()
            } label: {
                Label("播放公开远程测试音频", systemImage: "network")
            }

            if let statusText = playbackManager.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(playbackManager.playbackError == nil ? Color.secondary : Color.red)
            }
        }
    }

    private var musicLibrarySection: some View {
        Section("音乐库") {
            if let nasName = syncService.localStats.nasName {
                LabeledContent("当前 NAS", value: nasName)
            }
            LabeledContent("本地歌曲", value: "\(syncService.localStats.songCount)")
            LabeledContent("本地专辑", value: "\(syncService.localStats.albumCount)")
            LabeledContent("本地歌手", value: "\(syncService.localStats.artistCount)")
            LabeledContent("播放列表", value: "\(syncService.localStats.playlistCount)")
            LabeledContent("数据库大小", value: byteCount(syncService.localStats.databaseSize))
            LabeledContent("最近同步", value: syncService.localStats.lastSuccessfulSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "从未同步")
            LabeledContent("同步状态", value: syncStatusText)

            Button("立即同步") {
                Task { await syncService.syncLibrary() }
            }
            .disabled(viewModel.state != .connected || syncService.isSyncing)

            Button("取消同步") {
                syncService.cancelSync()
            }
            .disabled(!syncService.isSyncing)

            Button("重建音乐库索引") {
                showRebuildIndexConfirmation = true
            }
            .disabled(viewModel.state != .connected || syncService.isSyncing)
            .confirmationDialog(
                "确定要重建音乐库索引吗？",
                isPresented: $showRebuildIndexConfirmation,
                titleVisibility: .visible
            ) {
                Button("重建索引", role: .destructive) {
                    Task { await syncService.rebuildLibrary() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会重建当前 NAS 的本地音乐索引，不会删除登录凭证、NAS 配置或封面缓存。")
            }

            Button("清除本地音乐库索引", role: .destructive) {
                showClearIndexConfirmation = true
            }
            .disabled(syncService.isSyncing)
            .confirmationDialog(
                "确定要清除本地音乐库索引吗？",
                isPresented: $showClearIndexConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除索引", role: .destructive) {
                    Task { await syncService.clearLocalIndex() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会清除当前 NAS 的歌曲、专辑、歌手和播放列表索引。")
            }
        }
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private var syncStatusText: String {
        switch syncService.status {
        case .idle:
            return "空闲"
        case .preparing:
            return "准备同步"
        case .syncing(let current, let total, _):
            if let total { return "\(current)/\(total) 首" }
            return "已同步 \(current) 首"
        case .rebuildingAlbums:
            return "正在生成专辑索引"
        case .rebuildingArtists:
            return "正在生成歌手索引"
        case .completed(let date, let songCount, let albumCount, let artistCount):
            return "\(songCount) 首 · \(albumCount) 张 · \(artistCount) 位 · \(date.formatted(date: .abbreviated, time: .shortened))"
        case .cancelled:
            return "已取消"
        case .failed(let message):
            return message
        }
    }

    private var cacheManagementSection: some View {
        Section("缓存管理") {
            LabeledContent("封面缓存大小", value: viewModel.artworkCacheSizeText)
            LabeledContent("封面缓存文件数量", value: viewModel.artworkCacheFileCountText)

            if let artworkCacheErrorMessage = viewModel.artworkCacheErrorMessage {
                Text(artworkCacheErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                viewModel.clearArtworkCache()
            } label: {
                if viewModel.isClearingArtworkCache {
                    ProgressView()
                } else {
                    Text("清除封面缓存")
                }
            }
            .disabled(viewModel.isBusy || viewModel.isClearingArtworkCache)
        }
    }
}
