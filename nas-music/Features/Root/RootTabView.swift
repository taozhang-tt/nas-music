//
//  RootTabView.swift
//  nas-music
//
//  4 个底部 Tab（首页/音乐库/下载/设置），并把迷你播放器固定在 TabView 上方。
//

import SwiftUI

struct RootTabView: View {
    let musicLibrary: MusicLibraryProviding
    @ObservedObject var playbackManager: PlaybackManager
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var nasServerStore: NASServerStore

    @State private var isPlayerPresented = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(musicLibrary: musicLibrary, playbackManager: playbackManager)
            }
            .tabItem { Label("首页", systemImage: "house.fill") }

            NavigationStack {
                LibraryView(musicLibrary: musicLibrary, playbackManager: playbackManager)
            }
            .tabItem { Label("音乐库", systemImage: "music.note.list") }

            NavigationStack {
                DownloadsView(downloadManager: downloadManager)
            }
            .tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }

            NavigationStack {
                NASSettingsView(serverStore: nasServerStore)
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .safeAreaInset(edge: .bottom) {
            if playbackManager.currentSong != nil {
                MiniPlayerView(playbackManager: playbackManager) {
                    isPlayerPresented = true
                }
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerView(playbackManager: playbackManager)
        }
    }
}
