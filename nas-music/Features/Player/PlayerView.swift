//
//  PlayerView.swift
//  nas-music
//
//  深色风格全屏播放页：封面、歌曲名、歌手、进度条、播放控制按钮、队列入口。
//

import SwiftUI

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isQueuePresented = false

    init(playbackManager: PlaybackManager) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(playbackManager: playbackManager))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.playerBackgroundTop, AppTheme.playerBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header

                Spacer(minLength: 0)

                if let song = viewModel.song {
                    AlbumArtView(id: song.id, cornerRadius: 16)
                        .frame(width: 280, height: 280)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(song.artistName)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text("当前没有播放内容")
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 0)

                progressSection
                controlsSection
                bottomBar
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isQueuePresented) {
            QueueView(viewModel: viewModel.makeQueueViewModel())
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("正在播放")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Color.clear.frame(width: 22, height: 22)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { viewModel.progress },
                set: { viewModel.seek(toFraction: $0) }
            ))
            .tint(.white)

            HStack {
                Text(viewModel.currentTimeText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(viewModel.durationText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 36) {
            Button {
                viewModel.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(viewModel.isShuffled ? Color.accentColor : .white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.playPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.cycleRepeatMode()
            } label: {
                Image(systemName: viewModel.repeatMode.iconName)
                    .font(.title3)
                    .foregroundStyle(viewModel.repeatMode.isActive ? Color.accentColor : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                isQueuePresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    if viewModel.queueCount > 0 {
                        Text("\(viewModel.queueCount)")
                            .font(.caption)
                    }
                }
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
}
