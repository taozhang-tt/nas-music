//
//  RootTabView.swift
//  nas-music
//
//  4 个底部 Tab（首页/音乐库/下载/设置），用 tabViewBottomAccessory 把迷你播放器固定在
//  TabView 上方（不能用 .safeAreaInset(edge: .bottom)：iOS 26 的浮动 Tab Bar 下，
//  safeAreaInset 加进来的内容会顶替掉 Tab Bar 本身，而不是叠在它上面）。
//  PlaybackManager 从 @EnvironmentObject 拿（由 App 在根部注入），所有页面共享同一份播放状态。
//  selectedTab 用于让首页的 NAS 状态卡片能直接跳转到设置 Tab。
//

import SwiftUI

private enum RootTab: Hashable {
    case home, library, downloads, settings
}

struct RootTabView: View {
    let providerStore: MusicLibraryProviderStore
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var nasSessionManager: NASSessionManager
    @ObservedObject var musicLibrarySyncService: MusicLibrarySyncService
    @ObservedObject var metadataWritebackService: MetadataWritebackService

    @EnvironmentObject private var playbackManager: PlaybackManager
    @State private var isPlayerPresented = false
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(providerStore: providerStore, onNavigateToSettings: { selectedTab = .settings })
            }
            .tabItem { Label("首页", systemImage: "house.fill") }
            .tag(RootTab.home)

            NavigationStack {
                LibraryView(
                    providerStore: providerStore,
                    syncService: musicLibrarySyncService,
                    metadataWritebackService: metadataWritebackService,
                    sessionManager: nasSessionManager
                )
            }
            .tabItem { Label("音乐库", systemImage: "music.note.list") }
            .tag(RootTab.library)

            NavigationStack {
                DownloadsView(downloadManager: downloadManager)
            }
            .tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }
            .tag(RootTab.downloads)

            NavigationStack {
                NASSettingsView(
                    sessionManager: nasSessionManager,
                    syncService: musicLibrarySyncService,
                    metadataWritebackService: metadataWritebackService
                )
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(RootTab.settings)
        }
        .tabViewBottomAccessory(isEnabled: playbackManager.currentSong != nil) {
            MiniPlayerView {
                isPlayerPresented = true
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerView()
        }
    }
}
