//
//  DownloadsView.swift
//  nas-music
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel: DownloadsViewModel

    init(downloadManager: DownloadManager) {
        _viewModel = StateObject(wrappedValue: DownloadsViewModel(downloadManager: downloadManager))
    }

    var body: some View {
        List {
            if viewModel.items.isEmpty {
                ContentUnavailableView("暂无下载任务", systemImage: "arrow.down.circle")
            } else {
                ForEach(viewModel.items) { item in
                    row(for: item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.remove(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("下载管理")
    }

    private func row(for item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            AlbumArtView(id: item.song.id.uuidString, cornerRadius: 6)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.song.title)
                    .font(.body)
                    .lineLimit(1)
                Text(item.song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.status == .downloading || item.status == .paused {
                    ProgressView(value: item.progress)
                        .tint(item.status == .paused ? .secondary : .accentColor)
                }
            }

            Spacer()

            statusControl(for: item)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusControl(for item: DownloadItem) -> some View {
        switch item.status {
        case .queued:
            Text("等待中")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            Button {
                viewModel.pause(item)
            } label: {
                Image(systemName: "pause.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
        case .paused:
            Button {
                viewModel.resume(item)
            } label: {
                Image(systemName: "play.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .failed:
            Button {
                viewModel.retry(item)
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let repository = MockMusicRepository()
    let items = repository.songs.prefix(3).enumerated().map { index, song in
        DownloadItem(
            id: "download-\(song.id.uuidString)",
            song: song,
            status: index == 0 ? .completed : (index == 1 ? .failed : .downloading),
            progress: index == 0 ? 1 : (index == 1 ? 0.4 : 0.65)
        )
    }
    NavigationStack {
        DownloadsView(downloadManager: DownloadManager(items: items))
    }
}
