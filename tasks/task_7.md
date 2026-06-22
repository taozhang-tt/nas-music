基于当前 NASMusic 项目继续开发。

## 一、当前项目状态

已经完成：

1. SwiftUI 基础页面和高保真 UI。
2. PlaybackManager 播放内核。
3. 后台播放、锁屏控制、控制中心信息。
4. 群晖 DSM 登录和 NAS 配置管理。
5. Audio Station 音乐列表接入。
6. 真实 NAS 音乐播放。
7. 封面加载和封面缓存。
8. 播放诊断与修复，本地、远程和 NAS 音乐播放闭环已经通过。

本阶段不要修改已经稳定的播放逻辑。

## 二、本阶段目标

实现：

1. 将 NAS 音乐元数据同步到本地数据库。
2. App 优先从本地数据库展示音乐库。
3. 支持歌曲、专辑、歌手搜索。
4. 支持音乐库手动同步和重建索引。
5. 支持大规模音乐库分页查询。
6. NAS 暂时不可访问时，仍可浏览已经同步的音乐元数据。
7. 播放时仍然动态向 NAS 获取真实 stream URL。

## 三、技术方案

优先使用 GRDB 管理 SQLite。

如果项目已经稳定使用 SwiftData，可以继续使用 SwiftData，但需确保：

1. 支持数千到数万条歌曲记录。
2. 支持批量事务写入。
3. 支持分页查询。
4. 支持模糊搜索。
5. 数据库操作不阻塞主线程。

数据库中只保存音乐元数据，不保存：

* 音频文件
* 封面二进制
* password
* sid
* synotoken
* 完整 stream URL
* 完整封面 URL

## 四、目录结构

新增：

```text
Core/
├─ Database/
│  ├─ DatabaseManager.swift
│  ├─ DatabaseMigrator.swift
│  ├─ DatabaseError.swift
│  ├─ Records/
│  │  ├─ SongRecord.swift
│  │  ├─ AlbumRecord.swift
│  │  ├─ ArtistRecord.swift
│  │  ├─ PlaylistRecord.swift
│  │  └─ SyncStateRecord.swift
│  └─ Repositories/
│     ├─ SongRepository.swift
│     ├─ AlbumRepository.swift
│     ├─ ArtistRepository.swift
│     ├─ PlaylistRepository.swift
│     └─ SyncStateRepository.swift
├─ Music/
│  ├─ MusicLibrarySyncService.swift
│  ├─ AppMusicLibraryService.swift
│  └─ MusicLibrarySyncState.swift
```

## 五、数据库表设计

### 1. songs

```sql
CREATE TABLE songs (
    id TEXT PRIMARY KEY NOT NULL,
    nas_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    title TEXT NOT NULL,
    normalized_title TEXT,
    artist TEXT,
    normalized_artist TEXT,
    album TEXT,
    normalized_album TEXT,
    album_artist TEXT,
    duration REAL,
    track_number INTEGER,
    disc_number INTEGER,
    year INTEGER,
    genre TEXT,
    file_extension TEXT,
    bitrate INTEGER,
    sample_rate INTEGER,
    file_size INTEGER,
    cover_id TEXT,
    path TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    UNIQUE(nas_id, source_id)
);
```

创建索引：

```sql
CREATE INDEX idx_songs_nas_id
ON songs(nas_id);

CREATE INDEX idx_songs_title
ON songs(nas_id, normalized_title);

CREATE INDEX idx_songs_artist
ON songs(nas_id, normalized_artist);

CREATE INDEX idx_songs_album
ON songs(nas_id, normalized_album);

CREATE INDEX idx_songs_last_seen
ON songs(nas_id, last_seen_at);
```

### 2. albums

```sql
CREATE TABLE albums (
    id TEXT PRIMARY KEY NOT NULL,
    nas_id TEXT NOT NULL,
    source_key TEXT NOT NULL,
    title TEXT NOT NULL,
    normalized_title TEXT,
    artist TEXT,
    normalized_artist TEXT,
    album_artist TEXT,
    year INTEGER,
    song_count INTEGER NOT NULL DEFAULT 0,
    total_duration REAL,
    cover_id TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    UNIQUE(nas_id, source_key)
);
```

`source_key` 可按以下规则生成：

```text
normalizedAlbumTitle + "|" + normalizedAlbumArtist
```

需要避免同名专辑直接合并错误。

### 3. artists

```sql
CREATE TABLE artists (
    id TEXT PRIMARY KEY NOT NULL,
    nas_id TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    name TEXT NOT NULL,
    song_count INTEGER NOT NULL DEFAULT 0,
    album_count INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    UNIQUE(nas_id, normalized_name)
);
```

### 4. playlists

```sql
CREATE TABLE playlists (
    id TEXT PRIMARY KEY NOT NULL,
    nas_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT,
    song_count INTEGER NOT NULL DEFAULT 0,
    cover_id TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    UNIQUE(nas_id, source_id)
);
```

### 5. playlist_songs

```sql
CREATE TABLE playlist_songs (
    playlist_id TEXT NOT NULL,
    song_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    PRIMARY KEY(playlist_id, song_id)
);
```

### 6. sync_state

```sql
CREATE TABLE sync_state (
    nas_id TEXT PRIMARY KEY NOT NULL,
    status TEXT NOT NULL,
    last_full_sync_at REAL,
    last_successful_sync_at REAL,
    last_failed_sync_at REAL,
    last_error_message TEXT,
    synced_song_count INTEGER NOT NULL DEFAULT 0,
    total_song_count INTEGER,
    album_count INTEGER NOT NULL DEFAULT 0,
    artist_count INTEGER NOT NULL DEFAULT 0,
    playlist_count INTEGER NOT NULL DEFAULT 0,
    current_offset INTEGER NOT NULL DEFAULT 0
);
```

## 六、数据库 Record 和业务 Model 转换

数据库 Record 不要直接暴露给 SwiftUI。

为每个 Record 实现转换：

```swift
extension SongRecord {
    func toDomain() -> Song
}

extension Song {
    func toRecord(
        nasId: String,
        syncTime: Date
    ) -> SongRecord
}
```

要求：

1. UI 和 PlaybackManager 继续使用现有 `Song` 模型。
2. 数据库层使用 `SongRecord`。
3. 不能为了数据库改坏现有播放模型。
4. `MusicSource.synology` 中仍然保留 Audio Station 的歌曲 ID。
5. 不把播放 URL写入数据库。

## 七、Repository 接口

### SongRepository

实现：

```swift
protocol SongRepositoryProtocol {
    func upsert(
        songs: [Song],
        nasId: String,
        syncTime: Date
    ) async throws

    func fetchSongs(
        nasId: String,
        offset: Int,
        limit: Int
    ) async throws -> [Song]

    func fetchSongs(
        nasId: String,
        album: String,
        albumArtist: String?,
        offset: Int,
        limit: Int
    ) async throws -> [Song]

    func fetchSongs(
        nasId: String,
        artist: String,
        offset: Int,
        limit: Int
    ) async throws -> [Song]

    func search(
        nasId: String,
        keyword: String,
        offset: Int,
        limit: Int
    ) async throws -> [Song]

    func count(nasId: String) async throws -> Int

    func markMissingAsDeleted(
        nasId: String,
        lastSeenBefore syncTime: Date
    ) async throws

    func clear(nasId: String) async throws
}
```

### AlbumRepository

实现：

```swift
protocol AlbumRepositoryProtocol {
    func rebuildFromSongs(
        nasId: String,
        syncTime: Date
    ) async throws

    func fetchAlbums(
        nasId: String,
        offset: Int,
        limit: Int
    ) async throws -> [Album]

    func search(
        nasId: String,
        keyword: String,
        offset: Int,
        limit: Int
    ) async throws -> [Album]

    func count(nasId: String) async throws -> Int
}
```

### ArtistRepository

实现：

```swift
protocol ArtistRepositoryProtocol {
    func rebuildFromSongs(
        nasId: String,
        syncTime: Date
    ) async throws

    func fetchArtists(
        nasId: String,
        offset: Int,
        limit: Int
    ) async throws -> [Artist]

    func search(
        nasId: String,
        keyword: String,
        offset: Int,
        limit: Int
    ) async throws -> [Artist]

    func count(nasId: String) async throws -> Int
}
```

## 八、搜索文本标准化

新增：

```text
Core/Search/SearchTextNormalizer.swift
```

至少实现：

1. 去除首尾空格。
2. 转小写。
3. 合并连续空格。
4. 使用 `folding(options:locale:)` 处理大小写和音调差异。
5. 中文先使用原始文本匹配。
6. 英文搜索大小写不敏感。

示例：

```swift
func normalize(_ value: String) -> String
```

本阶段先使用 SQLite `LIKE` 搜索，不要求立即接 FTS5。

搜索字段：

* 歌曲名
* 歌手名
* 专辑名
* 专辑歌手

查询需要转义 `%` 和 `_`，避免它们被错误解释为通配符。

## 九、音乐库同步服务

新增：

```swift
@MainActor
final class MusicLibrarySyncService: ObservableObject
```

公开状态：

```swift
enum MusicLibrarySyncStatus: Equatable {
    case idle
    case preparing
    case syncing(
        current: Int,
        total: Int?,
        progress: Double?
    )
    case rebuildingAlbums
    case rebuildingArtists
    case completed(
        date: Date,
        songCount: Int,
        albumCount: Int,
        artistCount: Int
    )
    case cancelled
    case failed(message: String)
}
```

公开方法：

```swift
func syncLibrary() async
func cancelSync()
func rebuildLibrary() async
```

同步流程：

1. 检查当前默认 NAS。
2. 检查 NAS 登录状态。
3. 检查 Audio Station API 是否可用。
4. 记录本次 `syncStartedAt`。
5. offset 从 0 开始。
6. 每批拉取 200 首歌曲。
7. 每批通过数据库事务执行 upsert。
8. 更新已同步数量和进度。
9. 直到返回数量小于 limit，或已经达到 API 返回的 total。
10. 根据 songs 表重新生成 albums。
11. 根据 songs 表重新生成 artists。
12. 同步播放列表。
13. 将本次没有出现的旧记录标记为 `is_deleted = 1`。
14. 更新 sync_state。
15. 发布 completed 状态。

要求：

1. 不要一次性将全部歌曲保存在内存中。
2. 每批写库必须使用 transaction。
3. 同一时间只能存在一个同步任务。
4. 用户重复点击时不创建第二个任务。
5. 支持取消同步。
6. 同步失败不能清空旧数据。
7. 只有全量同步成功后才能标记缺失歌曲为删除。
8. 当前正在播放的歌曲即使被标记删除，也不能中断播放。
9. session 失效时立即停止同步并提示重新连接。
10. 同步过程不修改封面缓存。

## 十、同步失败保护

特别注意：

不能在同步执行到一半时调用：

```swift
markMissingAsDeleted(...)
```

只有满足以下条件时才能标记缺失记录：

1. 所有歌曲分页请求均成功。
2. 用户没有取消。
3. 数据库写入全部成功。
4. NAS session 没有失效。

否则必须保留旧音乐库。

## 十一、AppMusicLibraryService

新增：

```swift
@MainActor
final class AppMusicLibraryService: ObservableObject
```

UI 只依赖这个服务，不直接依赖数据库或远程 Provider。

实现：

```swift
func loadSongs(
    offset: Int,
    limit: Int
) async throws -> [Song]

func loadAlbums(
    offset: Int,
    limit: Int
) async throws -> [Album]

func loadArtists(
    offset: Int,
    limit: Int
) async throws -> [Artist]

func search(
    keyword: String
) async throws -> MusicSearchResult

func resolveStreamURL(
    for song: Song
) async throws -> URL
```

行为：

1. NAS 已连接且本地有索引：从本地数据库读取。
2. NAS 已连接但本地无索引：提示先同步。
3. NAS 未连接但有历史索引：允许浏览历史元数据，但点击播放时提示连接 NAS。
4. Debug Mock 模式：继续支持 MockMusicLibraryProvider。
5. 播放真实歌曲时，仍通过 `SynologyAudioStationProvider` 动态获取 URL。

## 十二、搜索功能

新增：

```text
Features/Search/
├─ SearchView.swift
├─ SearchViewModel.swift
├─ SearchResult.swift
└─ SearchResultSection.swift
```

搜索结果模型：

```swift
struct MusicSearchResult {
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty
    }
}
```

SearchViewModel 状态：

```swift
enum SearchViewState {
    case idle
    case searching
    case loaded(MusicSearchResult)
    case empty
    case failed(message: String)
}
```

要求：

1. 输入防抖 300ms。
2. 空关键字不查询数据库。
3. 取消上一次未完成的搜索任务。
4. 搜索歌曲、专辑、歌手。
5. 每类首屏最多显示 20 条。
6. 搜索不访问 NAS。
7. 点击歌曲后播放。
8. 点击专辑进入专辑详情页。
9. 点击歌手进入歌手歌曲列表。
10. 搜索结果继续复用已有 ArtworkView。

## 十三、音乐库页面改造

LibraryView 增加四个分类：

1. 歌曲
2. 专辑
3. 歌手
4. 播放列表

页面状态：

### 本地无索引

显示：

```text
尚未同步音乐库
同步后可以快速浏览和搜索 NAS 中的音乐。
```

按钮：

```text
立即同步
```

### 正在同步

显示：

* 已同步歌曲数量
* 总歌曲数量
* 同步进度条
* 当前阶段
* 取消同步按钮

### 已完成

显示：

* 歌曲数
* 专辑数
* 歌手数
* 最近同步时间
* 立即刷新按钮

### 同步失败

要求：

1. 继续展示旧的本地音乐数据。
2. 页面顶部显示非阻塞错误提示。
3. 提供重新同步按钮。
4. 不要用全屏错误页覆盖已有内容。

## 十四、列表分页

歌曲列表：

```text
每页 100 首
```

专辑列表：

```text
每页 50 张
```

歌手列表：

```text
每页 50 位
```

要求：

1. 首屏只加载第一页。
2. 接近列表底部时自动加载下一页。
3. 加载下一页时不能重复请求。
4. 已无更多数据时停止请求。
5. 下拉刷新触发音乐库同步，不是简单重读数据库。
6. 页面重新进入时优先展示已有数据。

## 十五、设置页音乐库管理

新增“音乐库”设置区。

展示：

1. 当前 NAS 名称。
2. 本地歌曲数量。
3. 专辑数量。
4. 歌手数量。
5. 最近成功同步时间。
6. 本地数据库大小。
7. 当前同步状态。

操作：

1. 立即同步。
2. 取消同步。
3. 重建音乐库索引。
4. 清除本地音乐库索引。

行为：

### 立即同步

保留现有数据并更新。

### 重建音乐库索引

流程：

1. 弹出确认框。
2. 清除当前 NAS 的音乐索引。
3. 重新执行完整同步。
4. 不删除登录凭证。
5. 不删除封面缓存。
6. 不删除用户设置。

### 清除本地音乐库索引

流程：

1. 弹出确认框。
2. 只清除当前 NAS 的歌曲、专辑、歌手和播放列表索引。
3. 不删除 NAS 配置。
4. 不删除 Keychain 凭证。
5. 不删除封面缓存。
6. 不影响正在播放的歌曲。

## 十六、多 NAS 隔离

所有数据库查询都必须带 `nas_id`。

要求：

1. 不同 NAS 的歌曲不能混在一起。
2. 同一个 source_id 在不同 NAS 中可以同时存在。
3. 切换默认 NAS 后，页面读取对应 NAS 的索引。
4. 清除索引时只能清除选中的 NAS。
5. 封面缓存继续使用 `nasId + coverId + size` 作为缓存 key。

## 十七、错误类型

新增：

```swift
enum MusicLibrarySyncError: LocalizedError {
    case nasNotConfigured
    case nasNotConnected
    case audioStationUnavailable
    case sessionExpired
    case networkUnavailable
    case requestFailed
    case decodingFailed
    case databaseWriteFailed
    case databaseReadFailed
    case cancelled
    case unknown
}
```

用户文案：

```text
nasNotConfigured:
请先添加 NAS 配置。

nasNotConnected:
请先连接 NAS 后再同步音乐库。

audioStationUnavailable:
当前 NAS 无法访问 Audio Station，请确认套件已经安装并启用。

sessionExpired:
NAS 登录状态已经过期，请重新连接。

networkUnavailable:
无法连接 NAS，请检查网络和 NAS 状态。

databaseWriteFailed:
本地音乐库写入失败，请稍后重试或重建索引。
```

## 十八、并发和线程要求

1. 网络请求不在主线程执行。
2. 数据库读写不在主线程执行。
3. SwiftUI 状态更新回到 MainActor。
4. 同步任务使用结构化并发。
5. 不创建无法管理的 detached Task。
6. 所有长任务支持取消。
7. 页面销毁时取消搜索任务，但不自动取消全局同步任务。
8. App 进入后台时允许当前批次完成，不要求长时间后台同步。

## 十九、日志和安全

日志允许记录：

* 同步开始和结束
* NAS 配置 ID 的非敏感短标识
* 当前 offset
* 当前批次数量
* 总歌曲数量
* 数据库写入耗时
* 搜索耗时
* 错误类型
* HTTP 状态码
* Synology 错误码

严禁记录：

* password
* sid
* synotoken
* 完整 stream URL
* 完整封面 URL
* 包含鉴权参数的请求 URL

## 二十、测试要求

新增单元测试：

```text
NASMusicTests/
├─ DatabaseMigrationTests.swift
├─ SongRepositoryTests.swift
├─ AlbumRepositoryTests.swift
├─ ArtistRepositoryTests.swift
├─ SearchTextNormalizerTests.swift
├─ MusicLibrarySyncServiceTests.swift
└─ AppMusicLibraryServiceTests.swift
```

覆盖：

1. 数据库首次创建。
2. 数据库重复初始化。
3. Song 批量 upsert。
4. 同一歌曲更新而不是重复插入。
5. 不同 NAS 的歌曲正确隔离。
6. 分页查询顺序正确。
7. 搜索歌曲名。
8. 搜索歌手名。
9. 搜索专辑名。
10. 同步成功后标记缺失歌曲。
11. 同步失败时不标记缺失歌曲。
12. 用户取消同步时保留旧数据。
13. session 失效时正确停止。
14. 清除指定 NAS 的索引不影响其他 NAS。
15. 数据库中不存在 password、sid、synotoken 和 stream URL。

## 二十一、不要做的事情

本阶段不要实现：

1. 音频离线下载。
2. 歌词。
3. QuickConnect。
4. Bonjour 自动发现。
5. CarPlay。
6. 播放统计。
7. 收藏。
8. 最近播放。
9. 智能歌单。
10. FTS5 全文索引。
11. 云端同步。
12. 重新设计播放器 UI。
13. 重构已经通过验收的 PlaybackManager。

## 二十二、交付要求

开发完成后输出：

1. 新增和修改的文件列表。
2. 数据库表结构说明。
3. 数据库版本号。
4. 音乐库同步流程说明。
5. 搜索实现说明。
6. 已完成的单元测试。
7. 尚未覆盖的边界情况。
8. 手工验收步骤。

