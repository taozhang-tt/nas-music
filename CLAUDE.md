# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目现状

NAS Music（Xcode target/bundle id 仍为 `nas-music` / `zero-tt.top.nas-music`，仅 Display Name
改为 "NAS Music"）是一个面向群晖等 NAS 的音乐播放客户端。SwiftUI + MVVM，7 个页面。已接入真实
群晖 DSM 登录（`SYNO.API.Auth`）和 Audio Station 音乐库（歌曲/专辑/歌手/播放列表 + 真实 AVPlayer
播放）；NAS 未连接时整个 App 透明回退到 Mock 数据源，不需要切换代码路径。没有第三方依赖（无 SPM
包、无 CocoaPods）、没有测试 target，也没有 CI 配置。

使用 Xcode 26.4.1 构建，Swift 5.0，iOS 部署目标 26.4，SwiftUI app 生命周期。项目开启了
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 和 `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`：
任何用到 `@Published` / `ObservableObject` 的文件都必须显式 `import Combine`，不能依赖
SwiftUI 间接重导出。

## 项目结构

`nas-music.xcodeproj` 使用 Xcode 的 `PBXFileSystemSynchronizedRootGroup`：往 `nas-music/` 下任意
子目录添加 `.swift` 文件即会被自动编译，不需要手动编辑 `project.pbxproj` 的 Sources。

```
nas-music/
  nas_musicApp.swift          组合根：创建 NASSessionManager / MusicLibraryProviderStore /
                               PlaybackManager 等，展示 RootTabView
  Core/
    Models/                   Song / Album / Artist / Playlist / MusicSource / NASConnectionConfig 等
    Music/                    MusicLibraryProvider 协议 + MusicLibraryViewState（页面状态枚举）
    Theme/AppTheme.swift       配色与封面渐变（占位封面用，无真实图片资源，AlbumArtView 暂未接入
                               Audio Station 的真实封面图）
    Components/                跨页面复用：AlbumArtView、SongRowView、SongListView、SectionHeaderView
    Extensions/                TimeInterval+Format（mm:ss / 时长文案）
    Session/NASSessionManager.swift   App 级 NAS 登录状态（NASConnectionConfig 存 UserDefaults，
                               sid/synotoken 只进 Keychain）
    Keychain/                  KeychainService（Security.framework 最小封装）+ NASCredentialStore
    Playback/                  AudioSessionManager（后台音频会话）/ NowPlayingInfoManager（锁屏信息）/
                               RemoteCommandManager（锁屏远程控制）
    Logging/AppLogger.swift    统一日志出口，sid/synotoken/password 永远 <redacted>
  Providers/                   数据与状态层
    Mock/MockMusicLibraryProvider.swift   离线样例数据，实现 MusicLibraryProvider
    Synology/                  SynologyAPIClient（HTTP 基础设施 + API Discovery）、
                               SynologyAuthService（DSM 登录/登出）、SynologyAPIError
      AudioStation/            SynologyAudioStationProvider（真实 Audio Station 接入）+
                               AudioStationModels（宽松 Decodable）+ AudioStationMapper +
                               AudioStationError
    MusicLibraryProviderStore.swift   按 NASSessionManager.state 在 Mock / Synology provider
                               之间切换，会话失效时回调 sessionManager.clearCredentials()
    PlaybackManager.swift       播放传输状态（队列/进度/随机/循环）。.mock 来源歌曲走 Timer 模拟
                               推进；.synology/.local 来源歌曲先 fetchStreamURL 再用真实 AVPlayer
                               播放，两条腿共用同一套 published 状态
    DownloadManager.swift       下载任务状态，Timer 模拟下载进度（功能本身仍是占位，未接入真实
                               离线下载）
  Features/                    每个页面一个 View + ViewModel
    Root/RootTabView.swift      4 个 Tab（首页/音乐库/下载/设置）+ 迷你播放器常驻 + 全屏播放器，
                               持有 selectedTab 状态以便首页 NAS 状态卡片跳转到设置 Tab
    Home/                      首页：搜索、NAS 状态卡片、收藏统计、最近添加、播放列表、全部歌曲入口
    Library/                   音乐库：歌曲/专辑/歌手分段 + 搜索 + 分页加载 + 下拉刷新 + 错误重试
    AlbumDetail/                专辑详情：通过 MusicLibraryProvider 按专辑名/歌手过滤歌曲（Album
                               不再内嵌歌曲列表）
    Player/                    PlayerView（深色风格全屏播放页，含 loading/error 态）+ MiniPlayerView
    Queue/                     播放队列（从 PlayerView 以 sheet 弹出）
    Downloads/                  下载管理：进度/状态/暂停继续重试
    Settings/                   NAS 设置：连接表单、登录状态、测试连接、诊断信息
```

### 依赖注入与 MVVM 边界

- `nas_musicApp.swift` 是唯一的组合根：创建 `NASSessionManager`、`MusicLibraryProviderStore`、
  `PlaybackManager`、`DownloadManager`，全部以**显式构造参数**（不是 `@EnvironmentObject`）逐层传给
  `RootTabView` 再传给各 Feature 的 View/ViewModel；`PlaybackManager` 只在 `.environmentObject`
  注入给整棵视图树。
- `MusicLibraryProviderStore` 是「当前应该用哪个 `MusicLibraryProvider`」的唯一决策点：订阅
  `NASSessionManager.$state`，已连接时用 `SynologyAudioStationProvider`，否则用
  `MockMusicLibraryProvider`。`HomeViewModel`/`LibraryViewModel` 都持有这个 store 而不是某个具体
  provider，并订阅 `$activeProvider` 在切换时自动重新加载，避免页面停留在切换前的数据上。
  `PlaybackManager` 通过 `updateMusicLibraryProvider(_:)` 接收同样的切换通知，用来解析
  `fetchStreamURL`。
- Provider 负责数据/状态（"是什么"），ViewModel 负责该页面的展示逻辑和用户操作转发
  （"怎么显示/怎么响应"），View 只做布局绑定。
- 需要镜像 `PlaybackManager` 状态的 ViewModel/View 直接用 `@EnvironmentObject` 持有它，或者通过订阅
  `playbackManager.objectWillChange` 转发自身 `objectWillChange` 来保持响应式更新（纯粹的 Provider
  引用属性不会自动触发 View 重新渲染）。
- `MiniPlayerView` 是跨 Tab 常驻的展示组件而非独立页面，直接持有 `PlaybackManager` 引用，没有
  单独的 ViewModel。

### 迷你播放器固定位置的写法

`RootTabView` 用 `TabView { ... }.safeAreaInset(edge: .bottom) { MiniPlayerView(...) }`
把迷你播放器钉在 TabBar 上方，四个 Tab 切换时常驻不消失；点击后用 `fullScreenCover` 弹出
深色风格的 `PlayerView`。

## 常用命令

主要工作流是在 Xcode 中构建运行（`open nas-music.xcodeproj`）。命令行方式：

```bash
# 在 iOS 模拟器上构建（如果系统默认 Developer Dir 只是 Command Line Tools，需要加 DEVELOPER_DIR）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project nas-music.xcodeproj -scheme nas-music \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 如果上面的 destination 找不到设备，先列出可用模拟器
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available

# 清理构建产物
xcodebuild -project nas-music.xcodeproj -scheme nas-music clean
```

目前没有测试 target，`xcodebuild test` 在添加测试 target 之前会直接失败。
