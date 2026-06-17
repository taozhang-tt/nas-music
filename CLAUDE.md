# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目现状

这是一个刚通过 Xcode 默认 SwiftUI 模板创建的 iOS 项目，目前只有模板自带的 "Hello, world!"
样板代码（`nas-music/ContentView.swift`、`nas-music/nas_musicApp.swift`）。项目没有任何第三方依赖
（无 SPM 包、无 CocoaPods）、没有测试 target，也没有 CI 配置。项目名 "nas-music" 暗示未来会做一个
基于 NAS 的音乐播放/串流客户端，但相关功能尚未开始开发。

## 项目结构

- `nas-music.xcodeproj` — Xcode 项目（单一 app target，bundle id 为 `zero-tt.top.nas-music`）
- `nas-music/nas_musicApp.swift` — `@main` App 入口，配置 `WindowGroup` scene
- `nas-music/ContentView.swift` — 根 SwiftUI 视图
- `nas-music/Assets.xcassets` — app 图标和强调色的资源目录

使用 Xcode 26.4.1 构建，Swift 5.0，iOS 部署目标 26.4，SwiftUI app 生命周期。

## 常用命令

主要工作流是在 Xcode 中构建运行（`open nas-music.xcodeproj`）。命令行方式：

```bash
# 在 iOS 模拟器上构建
xcodebuild -project nas-music.xcodeproj -scheme nas-music \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# 如果上面的 destination 找不到设备，先列出可用模拟器
xcrun simctl list devices available

# 清理构建产物
xcodebuild -project nas-music.xcodeproj -scheme nas-music clean
```

目前没有测试 target，`xcodebuild test` 在添加测试 target 之前会直接失败。
