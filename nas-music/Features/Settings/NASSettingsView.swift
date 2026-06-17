//
//  NASSettingsView.swift
//  nas-music
//

import SwiftUI

struct NASSettingsView: View {
    @StateObject private var viewModel: NASSettingsViewModel

    init(serverStore: NASServerStore) {
        _viewModel = StateObject(wrappedValue: NASSettingsViewModel(serverStore: serverStore))
    }

    var body: some View {
        List {
            Section("NAS 服务器") {
                ForEach(viewModel.servers) { server in
                    serverRow(server)
                }
            }

            Section("安全") {
                Toggle("记住密码（保存到 Keychain）", isOn: $viewModel.rememberCredentialsInKeychain)
                Label("仅支持 HTTPS 连接", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("NAS 设置")
    }

    private func serverRow(_ server: NASServerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                    Text(server.useQuickConnect ? server.host : "\(server.host):\(server.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(server.status)
            }

            Button {
                viewModel.testConnection(for: server)
            } label: {
                if server.status == .testing {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("正在连接…")
                    }
                } else {
                    Text("测试连接")
                }
            }
            .font(.caption)
            .disabled(server.status == .testing)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: ConnectionStatus) -> some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor(status).opacity(0.15))
            .foregroundStyle(badgeColor(status))
            .clipShape(Capsule())
    }

    private func badgeColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected: .green
        case .disconnected: .red
        case .testing: .orange
        }
    }
}
