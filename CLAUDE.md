# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目现状

NAS Music（Xcode target/bundle id 仍为 `nas-music` / `zero-tt.top.nas-music`，仅 Display Name
改为 "NAS Music"）是一个面向群晖等 NAS 的音乐播放客户端。当前是 SwiftUI + MVVM 的功能骨架：
7 个页面、Mock 数据、暂未接入任何真实网络/音频后端。没有第三方依赖（无 SPM 包、无 CocoaPods）、
没有测试 target，也没有 CI 配置。

使用 Xcode 26.4.1 构建，Swift 5.0，iOS 部署目标 26.4，SwiftUI app 生命周期。项目开启了
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 和 `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`：
任何用到 `@Published` / `ObservableObject` 的文件都必须显式 `import Combine`，不能依赖
SwiftUI 间接重导出。

## 项目结构

`nas-music.xcodeproj` 使用 Xcode 的 `PBXFileSystemSynchronizedRootGroup`：往 `nas-music/` 下任意
子目录添加 `.swift` 文件即会被自动编译，不需要手动编辑 `project.pbxproj` 的 Sources。

```
nas-music/
  nas_musicApp.swift          组合根：创建并注入 Provider，展示 RootTabView
  Core/
    Models/                   Song / Album / Artist / DownloadItem / NASServerProfile / RepeatMode
    Theme/AppTheme.swift       配色与封面渐变（占位封面用，无真实图片资源）
    Components/                跨页面复用：AlbumArtView、SongRowView、SectionHeaderView
    Extensions/                TimeInterval+Format（mm:ss / 时长文案）
  Providers/                   数据与状态层，未来替换为真实后端时只换这一层
    MusicLibraryProviding.swift / MockMusicLibraryProvider.swift   音乐库协议 + Mock 实现
    PlaybackManager.swift       播放传输状态（队列/进度/随机/循环），Timer 模拟播放推进
    DownloadManager.swift       下载任务状态，Timer 模拟下载进度
    NASServerStore.swift        NAS 服务器列表 + 模拟连接测试
  Features/                    每个页面一个 View + ViewModel
    Root/RootTabView.swift      4 个 Tab（首页/音乐库/下载/设置）+ 迷你播放器常驻 + 全屏播放器
    Home/                      首页：搜索、最近播放、收藏统计、最近添加
    Library/                   音乐库：歌曲/专辑/歌手分段 + 搜索
    AlbumDetail/                专辑详情：封面/信息/播放全部/曲目列表
    Player/                    PlayerView（深色风格全屏播放页）+ PlayerViewModel + MiniPlayerView
    Queue/                     播放队列（从 PlayerView 以 sheet 弹出）
    Downloads/                  下载管理：进度/状态/暂停继续重试
    Settings/                   NAS 设置：服务器列表、连接状态、测试连接
```

### 依赖注入与 MVVM 边界

- `nas_musicApp.swift` 是唯一的组合根：创建 `MockMusicLibraryProvider`、`PlaybackManager`、
  `DownloadManager`、`NASServerStore`，全部以**显式构造参数**（不是 `@EnvironmentObject`）逐层传给
  `RootTabView` 再传给各 Feature 的 View/ViewModel。这样可以避免「`@EnvironmentObject` 在 `init`
  里还未注入」的时序问题，未来要接入真实的 AudioStation/WebDAV Provider 时只需替换
  `MusicLibraryProviding` 的实现，上层无需改动。
- Provider 负责数据/状态（"是什么"），ViewModel 负责该页面的展示逻辑和用户操作转发
  （"怎么显示/怎么响应"），View 只做布局绑定。
- `PlayerViewModel`、`QueueViewModel` 等需要镜像 `PlaybackManager` 状态的 ViewModel，通过订阅
  `playbackManager.objectWillChange` 并转发自身 `objectWillChange` 来保持响应式更新（纯粹的
  Provider 引用属性不会自动触发 View 重新渲染）。
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
