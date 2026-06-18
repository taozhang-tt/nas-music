//
//  PlayerView.swift
//  nas-music
//
//  深色风格全屏播放页：封面、歌曲名、歌手、进度条、播放控制按钮、队列入口。
//  直接绑定 @EnvironmentObject 的 PlaybackManager，和其它页面共享同一份播放状态。
//

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager
    @Environment(\.dismiss) private var dismiss
    @State private var isQueuePresented = false

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

                if let song = playbackManager.currentSong {
                    ArtworkView(coverId: song.coverId, size: .large, cornerRadius: 16, placeholderSeed: song.id)
                        .frame(width: 280, height: 280)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                    VStack(spacing: 6) {
                        Text(song.title)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(song.artist ?? "未知歌手")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text("当前没有播放内容")
                        .foregroundStyle(.white.opacity(0.6))
                }

                if let playbackError = playbackManager.playbackError {
                    Text(playbackError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .onTapGesture { playbackManager.dismissPlaybackError() }
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
            QueueView()
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
                get: { playbackManager.progress },
                set: { playbackManager.seek(to: playbackManager.duration * $0) }
            ))
            .tint(.white)

            HStack {
                Text(playbackManager.currentTime.formattedAsMinutesSeconds)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(playbackManager.duration.formattedAsMinutesSeconds)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 36) {
            Button {
                playbackManager.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(playbackManager.isShuffled ? Color.accentColor : .white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button {
                playbackManager.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                playbackManager.toggle()
            } label: {
                if playbackManager.isLoadingStream {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.6)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(playbackManager.isLoadingStream)

            Button {
                playbackManager.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                playbackManager.repeatMode.cycle()
            } label: {
                Image(systemName: playbackManager.repeatMode.iconName)
                    .font(.title3)
                    .foregroundStyle(playbackManager.repeatMode.isActive ? Color.accentColor : .white.opacity(0.7))
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
                    if playbackManager.playlist.count > 0 {
                        Text("\(playbackManager.playlist.count)")
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

private func makePreviewPlaybackManager() -> PlaybackManager {
    let provider = MockMusicLibraryProvider()
    let manager = PlaybackManager(musicLibraryProvider: provider)
    manager.updatePlaylist(provider.songs, currentIndex: 0)
    manager.play()
    return manager
}

#Preview {
    PlayerView()
        .environmentObject(makePreviewPlaybackManager())
}
