//
//  NASMetadataEditorView.swift
//  nas-music
//

import SwiftUI

struct NASMetadataEditorView: View {
    @StateObject private var viewModel: NASMetadataEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showWriteConfirmation = false

    init(song: Song, service: MetadataWritebackService, sessionManager: NASSessionManager) {
        _viewModel = StateObject(wrappedValue: NASMetadataEditorViewModel(song: song, service: service, sessionManager: sessionManager))
    }

    var body: some View {
        Form {
            remoteInfoSection
            editSection
            previewSection
            statusSection
        }
        .navigationTitle("编辑 NAS 标签")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("写入 NAS 文件") { showWriteConfirmation = true }
                    .disabled(!viewModel.canWrite)
            }
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "这会修改 NAS 上的原始音乐文件标签。",
            isPresented: $showWriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("写入 NAS 文件", role: .destructive) {
                Task { await viewModel.write() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("其他用户和音乐播放器也可能看到修改后的信息。")
        }
    }

    private var remoteInfoSection: some View {
        Section("NAS 原始文件") {
            if viewModel.isLoading {
                ProgressView("加载远程标签…")
            } else if let remote = viewModel.remote {
                LabeledContent("格式", value: remote.format.uppercased())
                LabeledContent("文件大小", value: ByteCountFormatter.string(fromByteCount: remote.fileSize, countStyle: .file))
                LabeledContent("最后修改", value: remote.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("支持写回", value: (remote.writeSupported ?? true) ? "是" : "否")
                Text("revision: \(remote.revision)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("重新读取") { Task { await viewModel.load() } }
                    .disabled(viewModel.isLoading || viewModel.isWriting)
            } else {
                Button("重新加载") { Task { await viewModel.load() } }
            }
        }
    }

    private var editSection: some View {
        Section("标签") {
            TextField("歌曲名称", text: $viewModel.title)
            TextField("歌手", text: $viewModel.artist)
            TextField("专辑", text: $viewModel.album)
            TextField("专辑歌手", text: $viewModel.albumArtist)
            TextField("流派", text: $viewModel.genre)
            TextField("年份", text: $viewModel.year)
                .keyboardType(.numberPad)
            TextField("曲目编号", text: $viewModel.trackNumber)
                .keyboardType(.numberPad)
            TextField("碟片编号", text: $viewModel.discNumber)
                .keyboardType(.numberPad)
            Toggle("转换为简体", isOn: $viewModel.convertToSimplified)
            LabeledContent("写入前备份", value: "自动创建")
        }
        .disabled(!viewModel.isEditable)
    }

    private var previewSection: some View {
        Section("预览") {
            Button("生成预览") {
                Task { await viewModel.generatePreview() }
            }
            .disabled(!viewModel.canGeneratePreview)

            if let preview = viewModel.preview {
                MetadataDiffView(before: preview.before, after: preview.after)
                ForEach(preview.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            MetadataWriteProgressView(isWriting: viewModel.isWriting, message: viewModel.successMessage)
            if let message = viewModel.informationalMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
