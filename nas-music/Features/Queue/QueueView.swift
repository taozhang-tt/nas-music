//
//  QueueView.swift
//  nas-music
//
//  播放队列：当前播放 + 即将播放，可切歌、可从队列移除。
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var viewModel: QueueViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let currentIndex = viewModel.queue.indices.contains(viewModel.currentIndex) ? viewModel.currentIndex : nil {
                    Section("正在播放") {
                        row(for: viewModel.queue[currentIndex], at: currentIndex)
                    }
                }

                let upcoming = viewModel.queue.indices.filter { $0 > viewModel.currentIndex }
                if !upcoming.isEmpty {
                    Section("接下来播放") {
                        ForEach(upcoming, id: \.self) { index in
                            row(for: viewModel.queue[index], at: index)
                        }
                    }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(for song: Song, at index: Int) -> some View {
        SongRowView(song: song, isPlaying: viewModel.isCurrent(index))
            .contentShape(Rectangle())
            .onTapGesture { viewModel.selectSong(at: index) }
            .swipeActions(edge: .trailing) {
                if !viewModel.isCurrent(index) {
                    Button(role: .destructive) {
                        viewModel.removeSong(at: index)
                    } label: {
                        Label("移除", systemImage: "trash")
                    }
                }
            }
    }
}
