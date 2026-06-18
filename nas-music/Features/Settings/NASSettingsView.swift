//
//  NASSettingsView.swift
//  nas-music
//

import SwiftUI

struct NASSettingsView: View {
    @StateObject private var viewModel: NASSettingsViewModel

    @AppStorage("nas.settings.allowHTTPLANTesting") private var allowHTTPLANTesting = false
    @AppStorage("nas.settings.showDiagnostics") private var showDiagnostics = false

    @State private var showDeleteConfirmation = false
    @State private var showClearCredentialConfirmation = false

    init(sessionManager: NASSessionManager) {
        _viewModel = StateObject(wrappedValue: NASSettingsViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        Form {
            statusSection
            formSection
            actionsSection
            advancedSection
            cacheManagementSection
        }
        .navigationTitle("NAS 设置")
        .disabled(viewModel.isBusy)
        .task { await viewModel.loadArtworkCacheStats() }
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
