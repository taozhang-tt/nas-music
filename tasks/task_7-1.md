# 第 7.1 步：将音乐元数据写回群晖 NAS 文件

## 当前状态

已完成第一版可用闭环：

1. iOS 端新增 NASMusic Agent 配置、健康检查、测试 FLAC 编辑入口、预览和写入 UI。
2. NASMusic Agent 支持 token 鉴权、sourceId 到真实文件路径索引、路径白名单校验、revision 冲突检测、备份、原子替换和 rollback API。
3. 已支持 MP3 ID3v2.4 与 FLAC Vorbis Comment 标签读写，不重新编码音频。
4. 已支持轻量繁体转简体预览；完整 OpenCC 后续接入。
5. 已提供 Synology 服务化部署脚本，支持 install/start/stop/restart/status/logs，后台运行并集中管理 binary/config/data/log/pid/backup。
6. 已在 NAS `test-flac` 上验证：health、读取标签、生成预览、App 写入、重新读取、服务化直连 `http://sh.zero-tt.top:2302`。
7. 已验证：`go test ./...` 通过，iOS `xcodebuild` 构建通过。

## 一、目标

实现真正的 NAS 音乐标签编辑能力。

用户在 iOS App 中修改：

* 歌曲名称
* 歌手
* 专辑
* 专辑歌手
* 流派
* 年份
* 曲目编号
* 碟片编号

保存后，修改必须写入群晖 NAS 上的原始音频文件。

完成后：

1. NASMusic 重新同步时能读取修改后的标签。
2. 其他群晖账号可以读取修改后的标签。
3. DS audio、Audio Station 和其他音乐播放器能看到修改后的信息。
4. 不对音频数据重新编码。
5. 不损失音质。

## 二、总体架构

新增 NAS 端服务：

```text
NASMusic Agent
```

架构：

```text
iOS NASMusic
    │
    │ HTTPS / JSON
    ▼
NASMusic Agent
    │
    ├── 鉴权与权限检查
    ├── 音乐文件路径解析
    ├── OpenCC 繁体转简体
    ├── TagLib 音频标签读写
    ├── 文件备份与原子替换
    ├── 写入结果校验
    └── 群晖音乐索引刷新状态
```

iOS App 不直接传递任意服务器文件路径。

App 只能发送：

```text
nasId
songSourceId
期望文件版本
修改字段
```

由 Agent 根据 songSourceId 查找并验证真实文件。

## 三、写回 Provider 抽象

在 iOS 项目新增：

```text
Core/MetadataWriteback/
├── MetadataWritebackProvider.swift
├── NASAgentMetadataWritebackProvider.swift
├── MetadataWritebackModels.swift
├── MetadataWritebackError.swift
└── MetadataWritebackService.swift
```

协议：

```swift
protocol MetadataWritebackProvider {
    func readRemoteMetadata(
        for song: Song
    ) async throws -> RemoteAudioMetadata

    func previewUpdate(
        song: Song,
        patch: AudioMetadataPatch
    ) async throws -> MetadataUpdatePreview

    func writeMetadata(
        song: Song,
        patch: AudioMetadataPatch,
        expectedRevision: String
    ) async throws -> MetadataWriteResult

    func rollback(
        operationId: String
    ) async throws
}
```

## 四、NASMusic Agent 技术方案

优先实现为独立 HTTP 服务。

推荐目录：

```text
nas-music-agent/
├── cmd/server/
├── internal/api/
├── internal/auth/
├── internal/config/
├── internal/library/
├── internal/metadata/
├── internal/opencc/
├── internal/taglib/
├── internal/writeback/
├── internal/backup/
├── internal/indexing/
└── internal/jobs/
```

服务职责：

1. 读取音频标签。
2. 修改音频标签。
3. 批量繁体转简体。
4. 写入前生成预览。
5. 写入前检查文件版本。
6. 写入临时文件。
7. 校验临时文件。
8. 原子替换原文件。
9. 保存短期回滚备份。
10. 返回写入结果。

## 五、Agent API

### 1. 服务状态

```http
GET /v1/health
```

响应：

```json
{
  "status": "ok",
  "version": "1.0.0",
  "tagWriterAvailable": true,
  "openCCAvailable": true
}
```

### 2. 读取远程标签

```http
GET /v1/songs/{sourceId}/metadata
```

响应：

```json
{
  "sourceId": "12345",
  "revision": "sha256-or-file-revision",
  "format": "flac",
  "fileSize": 123456789,
  "modifiedAt": "2026-06-22T10:00:00Z",
  "metadata": {
    "title": "後來",
    "artist": "劉若英",
    "album": "我等你",
    "albumArtist": "劉若英",
    "genre": "流行",
    "year": 1999,
    "trackNumber": 1,
    "discNumber": 1
  }
}
```

### 3. 修改预览

```http
POST /v1/songs/{sourceId}/metadata/preview
```

请求：

```json
{
  "convertToSimplified": true,
  "fields": [
    "title",
    "artist",
    "album",
    "albumArtist",
    "genre"
  ],
  "manualPatch": {}
}
```

响应：

```json
{
  "before": {
    "title": "後來",
    "artist": "劉若英"
  },
  "after": {
    "title": "后来",
    "artist": "刘若英"
  },
  "warnings": []
}
```

### 4. 写入标签

```http
PATCH /v1/songs/{sourceId}/metadata
```

请求：

```json
{
  "expectedRevision": "revision-before-edit",
  "patch": {
    "title": "后来",
    "artist": "刘若英",
    "album": "我等你",
    "albumArtist": "刘若英"
  },
  "createBackup": true
}
```

响应：

```json
{
  "operationId": "operation-uuid",
  "newRevision": "new-file-revision",
  "backupCreated": true,
  "indexStatus": "pending",
  "metadata": {
    "title": "后来",
    "artist": "刘若英",
    "album": "我等你"
  }
}
```

### 5. 回滚

```http
POST /v1/operations/{operationId}/rollback
```

## 六、文件写入流程

禁止直接在原文件上无保护写入。

必须执行：

```text
1. 根据 sourceId 查找真实音乐文件
2. 验证路径位于允许的音乐目录内
3. 检查文件读写权限
4. 读取 size、mtime、hash 或 revision
5. 比较 expectedRevision
6. 获取文件级写锁
7. 在同目录创建临时文件
8. 将原文件复制到临时文件
9. 在临时文件上修改标签
10. 重新读取临时文件标签
11. 验证修改结果
12. 验证音频时长、编码、采样率等未异常变化
13. 将原文件移动到备份位置
14. 将临时文件原子重命名为原文件
15. 恢复原文件权限和所有者
16. 返回新 revision
17. 释放文件锁
18. 通知 iOS App 重新同步该歌曲
```

临时文件必须和原文件位于同一文件系统，以便使用原子 rename。

## 七、并发冲突处理

写入请求必须携带：

```text
expectedRevision
```

revision 至少基于：

```text
文件大小
修改时间
文件 inode 或文件标识
可选快速 hash
```

如果文件在用户打开编辑页后已被其他程序修改：

```http
409 Conflict
```

App 提示：

```text
该音乐文件已被其他用户修改，请重新加载最新信息后再保存。
```

禁止静默覆盖其他用户的修改。

## 八、标签写入工具

优先使用 TagLib。

第一版支持：

```text
MP3
FLAC
M4A / MP4 / ALAC / AAC
OGG Vorbis
Opus
```

第二阶段再验证：

```text
WAV
AIFF
APE
WMA
DSF
DFF
WavPack
```

对于不确定可以安全写入的格式，第一版只允许读取，不允许写入。

返回：

```text
该文件格式暂不支持安全修改标签。
```

## 九、标签映射

统一领域字段：

```text
title
artist
album
albumArtist
genre
year
trackNumber
trackTotal
discNumber
discTotal
comment
composer
```

格式映射示例：

### MP3

```text
TITLE        → TIT2
ARTIST       → TPE1
ALBUM        → TALB
ALBUM_ARTIST → TPE2
GENRE        → TCON
YEAR         → TDRC
TRACK        → TRCK
DISC         → TPOS
```

### FLAC / OGG / Opus

```text
TITLE
ARTIST
ALBUM
ALBUMARTIST
GENRE
DATE
TRACKNUMBER
TRACKTOTAL
DISCNUMBER
DISCTOTAL
```

### M4A / MP4 / ALAC

使用对应 MP4/iTunes metadata atom。

不得删除不认识的原始标签。

不得在用户只修改标题时清空：

```text
歌词
封面
作曲人
注释
自定义字段
ReplayGain
排序字段
```

## 十、繁体转简体

Agent 使用 OpenCC。

默认转换配置：

```text
t2s
```

转换字段：

```text
歌曲名称
歌手
专辑
专辑歌手
流派
可选作曲人
```

不要转换：

```text
文件路径
文件扩展名
MusicBrainz ID
ISRC
哈希
URL
技术参数
```

保存前必须显示转换预览。

用户可以取消选中某个字段。

例如：

```text
标题：後來 → 后来
歌手：劉若英 → 刘若英
专辑：我等你 → 我等你
```

## 十一、iOS 编辑页面

新增：

```text
Features/MetadataEditor/
├── NASMetadataEditorView.swift
├── NASMetadataEditorViewModel.swift
├── MetadataDiffView.swift
├── MetadataWriteProgressView.swift
└── BatchMetadataEditorView.swift
```

页面展示：

1. NAS 原始标签。
2. 简体转换预览。
3. 用户修改后的内容。
4. 当前文件格式。
5. 文件大小。
6. 最后修改时间。
7. 是否支持写回。
8. 备份选项。

操作：

```text
转换为简体
手动编辑
写回 NAS
取消
恢复上一次修改
```

保存按钮文案：

```text
写入 NAS 文件
```

保存前弹出确认：

```text
这会修改 NAS 上的原始音乐文件标签。
其他用户和音乐播放器也可能看到修改后的信息。
```

## 十二、批量转换

支持以下批量范围：

```text
当前歌曲
当前专辑
当前歌手
用户选中的歌曲
```

批量操作必须先生成预览。

批量任务流程：

```text
创建任务
→ 顺序或有限并发处理
→ 每首文件独立锁定
→ 逐首返回成功或失败
→ 支持取消后续任务
→ 已成功文件不自动回滚
```

默认最大并发：

```text
2
```

避免大量磁盘随机写入。

批量结果显示：

```text
成功 18 首
失败 2 首
跳过 1 首
```

## 十三、文件名重命名

第一版不自动重命名文件。

设置中提供实验选项：

```text
同时重命名音乐文件
```

默认关闭。

启用后，重命名规则必须单独配置，例如：

```text
{track:02} - {title}.{ext}
```

重命名前检查：

1. 同名文件冲突。
2. 非法字符。
3. 歌词同名文件。
4. 外部封面文件。
5. 播放列表引用。
6. 当前是否正在播放。

标签写入和文件名重命名必须是两个独立操作。

## 十四、备份与回滚

默认保留最近 7 天的修改备份。

备份目录：

```text
/music/.nasmusic-backup/
```

或者配置到独立目录：

```text
/volume1/nasmusic-backup/
```

备份记录包含：

```text
operationId
sourceId
原文件路径
备份文件路径
修改前 revision
修改后 revision
修改前标签
修改后标签
创建时间
```

支持：

```text
恢复上一次修改
```

备份清理不得删除仍关联有效回滚记录的文件。

## 十五、群晖索引处理

文件写入完成后：

1. 更新文件修改时间。
2. 等待群晖索引服务检测文件变化。
3. 轮询 Audio Station 获取该歌曲信息。
4. 如果读取到新标签，状态改为 indexed。
5. 超时后状态改为 pending。
6. 不因索引暂未刷新而回滚已经成功写入的文件。

UI 状态：

```text
文件已修改，等待群晖更新音乐索引
```

设置页增加：

```text
重新同步音乐库
```

不要在第一版中依赖未经验证的群晖内部索引命令。

## 十六、数据库扩展

新增：

```sql
CREATE TABLE metadata_write_operations (
    id TEXT PRIMARY KEY NOT NULL,
    nas_id TEXT NOT NULL,
    song_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    status TEXT NOT NULL,
    old_revision TEXT,
    new_revision TEXT,
    before_metadata_json TEXT,
    after_metadata_json TEXT,
    backup_available INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at REAL NOT NULL,
    completed_at REAL
);
```

SongRecord 增加：

```text
remote_revision
metadata_write_status
metadata_last_written_at
metadata_index_status
```

状态：

```swift
enum MetadataWriteStatus {
    case idle
    case previewing
    case writing
    case written
    case waitingForIndex
    case indexed
    case conflict
    case failed
}
```

## 十七、安全要求

Agent 必须：

1. 只监听局域网或指定网络接口。
2. 支持 HTTPS。
3. 使用独立 API Token。
4. Token 保存到 iOS Keychain。
5. 限制允许访问的音乐根目录。
6. 拒绝 `..` 等路径穿越。
7. 不接受客户端传递的任意绝对路径。
8. 以非 root 用户运行。
9. 只赋予音乐目录所需读写权限。
10. 日志中不记录完整 Token。
11. 日志中不记录群晖密码。
12. 对写入接口做频率限制。
13. 所有修改写入审计日志。

## 十八、权限检查

Agent 启动时检查：

```text
音乐目录是否存在
是否可读
是否可写
临时目录是否可写
备份目录是否可写
TagLib 是否可用
OpenCC 是否可用
```

iOS 设置页增加 Agent 状态：

```text
已连接
版本
标签写入可用
繁简转换可用
音乐目录可写
备份目录可写
```

## 十九、错误类型

```swift
enum MetadataWritebackError: LocalizedError {
    case agentUnavailable
    case unauthorized
    case songNotFound
    case pathNotAllowed
    case permissionDenied
    case unsupportedFormat
    case fileChanged
    case fileLocked
    case insufficientSpace
    case backupFailed
    case tagWriteFailed
    case validationFailed
    case replacementFailed
    case rollbackFailed
    case indexingPending
    case unknown
}
```

主要提示：

```text
fileChanged:
该文件已被其他用户修改，请重新加载后再保存。

permissionDenied:
NASMusic Agent 没有修改该音乐文件的权限。

unsupportedFormat:
当前音乐格式暂不支持安全写入标签。

insufficientSpace:
NAS 可用空间不足，无法创建临时文件或备份。

indexingPending:
文件标签已经修改，正在等待群晖更新音乐索引。
```

## 二十、测试要求

Agent 测试：

1. MP3 标签读取和写入。
2. FLAC 标签读取和写入。
3. M4A 标签读取和写入。
4. OGG/Opus 标签读取和写入。
5. 繁体转简体。
6. 封面写入后仍然存在。
7. 歌词标签写入后仍然存在。
8. ReplayGain 标签不丢失。
9. 音频时长不变化。
10. 音频编码参数不变化。
11. 写入失败时原文件不损坏。
12. 临时文件校验失败时不替换原文件。
13. expectedRevision 冲突返回 409。
14. 非法路径请求被拒绝。
15. 只读文件返回权限错误。
16. 磁盘空间不足时安全失败。
17. 回滚成功。
18. 多请求修改同一个文件时正确加锁。

iOS 测试：

1. 加载远程标签。
2. 生成简体预览。
3. 保存单首歌曲。
4. 写入期间显示进度。
5. 冲突后提示重新加载。
6. 写入后更新本地数据库。
7. 修改当前播放歌曲不打断播放。
8. 锁屏信息更新为新标签。
9. 重新同步后仍读取到新标签。
10. Agent 不可用时正确提示。

## 二十一、验收标准

1. 将“後來”写回为“后来”。
2. 将“劉若英”写回为“刘若英”。
3. Audio Station 重新读取后显示简体标签。
4. 另一个群晖账号读取歌曲时显示简体标签。
5. 下载该文件到电脑后，第三方播放器读取到简体标签。
6. 音频内容不重新编码。
7. 音质、时长、采样率和位深不发生变化。
8. 内嵌封面和歌词不丢失。
9. 修改失败时原文件保持完整。
10. 支持恢复上一次修改。
11. 批量转换支持预览和进度。
12. 不默认修改文件名。
13. 所有安全和冲突测试通过。
