基于当前 NASMusic 项目继续开发。

目标：接入 Synology Audio Station 音乐库列表，并让 App 可以播放真实 NAS 上的音乐。

当前状态：
1. SwiftUI Mock UI 已完成。
2. PlaybackManager 已完成。
3. 后台播放、锁屏控制、控制中心播放信息已完成。
4. NAS 连接配置、DSM 登录、Keychain 凭证保存已完成。
5. 当前音乐库仍使用 Mock 数据。

本阶段任务：

一、新增音乐数据源抽象

新增：

Core/Music/MusicLibraryProvider.swift

定义协议：

protocol MusicLibraryProvider {
    func fetchSongs(offset: Int, limit: Int) async throws -> [Song]
    func fetchAlbums(offset: Int, limit: Int) async throws -> [Album]
    func fetchArtists(offset: Int, limit: Int) async throws -> [Artist]
    func fetchPlaylists(offset: Int, limit: Int) async throws -> [Playlist]
    func fetchStreamURL(for song: Song) async throws -> URL
}

当前实现两个 Provider：

1. MockMusicLibraryProvider
   - 保留现有 Mock 数据
   - 用于无 NAS 连接时开发和预览

2. SynologyAudioStationProvider
   - 使用真实 NAS API
   - 依赖 NASSessionManager、SynologyAPIClient、Keychain 中的 sid/synotoken

二、统一音乐模型

检查或新增以下模型：

Core/Models/Song.swift
Core/Models/Album.swift
Core/Models/Artist.swift
Core/Models/Playlist.swift

Song 至少包含：

struct Song: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let fileExtension: String?
    let bitrate: Int?
    let sampleRate: Int?
    let fileSize: Int64?
    let coverId: String?
    let source: MusicSource
}

MusicSource：

enum MusicSource: Codable, Equatable {
    case mock(url: String)
    case synology(audioStationId: String)
    case local(fileURL: String)
}

注意：
1. 不要把播放 URL 长期保存进 Song。
2. Song 只保存 Audio Station 的媒体 id。
3. 播放前通过 fetchStreamURL(for:) 动态换取 stream URL。
4. 如果 stream URL 带 sid，不要打印完整 URL。

三、实现 Audio Station API Discovery

在 SynologyAPIClient 中新增：

func queryAPIInfo(_ apis: [String]) async throws -> [String: SynologyAPIInfo]

本阶段至少查询：

1. SYNO.AudioStation.Info
2. SYNO.AudioStation.Playlist
3. SYNO.AudioStation.Folder
4. SYNO.AudioStation.Song
5. SYNO.AudioStation.Album
6. SYNO.AudioStation.Artist
7. SYNO.AudioPlayer.Stream

请求形式：

GET /webapi/entry.cgi
?api=SYNO.API.Info
&version=1
&method=query
&query=SYNO.AudioStation.Info,SYNO.AudioStation.Playlist,SYNO.AudioStation.Folder,SYNO.AudioStation.Song,SYNO.AudioStation.Album,SYNO.AudioStation.Artist,SYNO.AudioPlayer.Stream

实现要求：
1. 不要假设所有 API 都存在。
2. 返回结果中不存在的 API 要标记为 unavailable。
3. 每个 API 请求时使用 discovery 返回的 path 和 maxVersion。
4. 如果 Audio Station 未安装或未启用，UI 显示明确错误。
5. 在诊断日志中只打印 API name、path、minVersion、maxVersion，不打印 sid/synotoken。

四、实现 SynologyAudioStationProvider

新增：

Providers/Synology/AudioStation/SynologyAudioStationProvider.swift
Providers/Synology/AudioStation/AudioStationModels.swift
Providers/Synology/AudioStation/AudioStationMapper.swift

职责：

1. 初始化时读取 NASSessionManager 当前连接。
2. 通过 Keychain 读取 sid/synotoken。
3. 调用 API Discovery。
4. 拉取歌曲列表。
5. 拉取播放列表。
6. 将 Synology 返回结构映射为 App 内 Song / Album / Artist / Playlist。
7. 获取真实播放 stream URL。

五、歌曲列表 API

优先尝试使用 Audio Station 的歌曲列表 API。

由于不同 DSM / Audio Station 版本可能返回字段不同，实现时要宽松解析。

建议请求参数：

api = SYNO.AudioStation.Song
method = list
library = all
offset = offset
limit = limit
additional = song_tag,song_audio,album_tag
_sid = sid

注意：
1. version 使用 API Discovery 返回的 maxVersion。
2. path 使用 API Discovery 返回的 path。
3. 如果 SYNO.AudioStation.Song 不存在，不要崩溃。
4. 如果返回字段缺失，Song 中对应字段填 nil。
5. 一次默认 limit = 100。
6. 支持分页加载。

响应解析建议：

struct SynologyAudioStationSongListResponse: Decodable {
    let success: Bool
    let data: SongListData?
    let error: SynologyAPIErrorBody?
}

struct SongListData: Decodable {
    let total: Int?
    let offset: Int?
    let songs: [SynologySong]?
}

SynologySong 使用宽松 Decodable：
1. id
2. title
3. artist
4. album
5. album_artist
6. duration
7. additional
8. cover
9. path
10. type

如果实际字段名不同，用 CodingKeys 兼容多种命名。

六、播放 URL 获取

新增方法：

func fetchStreamURL(for song: Song) async throws -> URL

优先使用：

api = SYNO.AudioPlayer.Stream
method = stream
version = discovery maxVersion，如果失败则尝试 version = 2
id = song.source.audioStationId
_sid = sid

返回处理：
1. 如果接口直接返回可播放 URL，则使用返回 URL。
2. 如果接口本身就是二进制流地址，则构造 URL 给 AVPlayer。
3. 如果需要转码，后续版本再支持，本阶段先不做强制转码。
4. stream URL 不做持久化。
5. stream URL 不打印完整日志。

七、PlaybackManager 改造

当前 play(song) 可能直接使用 song.url。

改造为：

func play(song: Song) {
    Task {
        let streamURL = try await musicLibraryProvider.fetchStreamURL(for: song)
        await MainActor.run {
            self.play(url: streamURL, song: song)
        }
    }
}

要求：
1. Mock Song 仍然可以直接播放。
2. Synology Song 播放前动态获取 stream URL。
3. 获取 URL 期间播放器显示 loading。
4. 获取失败时显示错误，不要把播放器状态卡死。
5. 当前播放队列支持混合 Mock / Synology，但 UI 默认只展示当前 Provider 的数据。

八、音乐库页面接入真实数据

修改 LibraryView / HomeView / AlbumDetailView：

1. 如果 NAS 已连接：
   - 使用 SynologyAudioStationProvider 拉取真实歌曲。
2. 如果 NAS 未连接：
   - 继续使用 MockMusicLibraryProvider。
3. 音乐库页面增加 loading 状态。
4. 音乐库页面增加 empty 状态。
5. 音乐库页面增加 error 状态。
6. 增加“重新加载”按钮。
7. 支持下拉刷新。
8. 支持分页加载更多。

页面状态枚举：

enum MusicLibraryViewState {
    case idle
    case loading
    case loaded
    case empty
    case failed(message: String)
}

九、首页改造

首页原来的 Mock 推荐内容暂时保留，但增加真实数据入口：

1. 最近添加：取前 20 首真实歌曲。
2. 全部歌曲：进入 SongListView。
3. 播放列表：如果 API 可用则展示。
4. NAS 状态卡片：
   - 未连接：提示去设置页连接 NAS。
   - 已连接：展示 NAS 名称和最近同步时间。
   - 失败：展示错误和重新连接入口。

十、错误处理

新增 AudioStationError：

enum AudioStationError: LocalizedError {
    case audioStationNotInstalled
    case apiUnavailable(String)
    case emptyLibrary
    case invalidSongId
    case streamURLUnavailable
    case permissionDenied
    case sessionExpired
    case unsupportedResponse
    case decodingFailed
    case networkError(Error)
}

用户提示文案：

audioStationNotInstalled:
当前 NAS 未检测到 Audio Station，请先在群晖套件中心安装并启用 Audio Station。

apiUnavailable:
当前 Audio Station 接口不可用，请确认 DSM / Audio Station 版本是否支持该功能。

emptyLibrary:
没有找到音乐文件。请确认 Audio Station 已完成音乐索引。

permissionDenied:
当前账号没有访问 Audio Station 音乐库的权限。

sessionExpired:
登录状态已过期，请重新连接 NAS。

streamURLUnavailable:
无法获取歌曲播放地址，请稍后重试。

十一、Session 过期处理

如果任意 Audio Station API 返回 session 失效：

1. 标记 NASConnectionState 为 disconnected 或 failed。
2. 清理当前 sid/synotoken。
3. UI 提示重新登录。
4. 不要反复自动重试登录，因为没有保存密码。
5. 保留 NASConnectionConfig，方便用户重新输入密码连接。

十二、日志与安全要求

1. 不打印 password。
2. 不打印 sid。
3. 不打印 synotoken。
4. 不打印完整 stream URL。
5. 不打印带鉴权参数的完整 request URL。
6. 可以打印：
   - API name
   - HTTP status code
   - Synology error code
   - response decode error
   - 请求耗时
7. Debug 模式可以开启详细日志。
8. Release 模式关闭敏感网络日志。

十三、不要做的事情

1. 不要做离线下载。
2. 不要做本地数据库缓存。
3. 不要做歌词。
4. 不要做 QuickConnect。
5. 不要做 Bonjour 自动发现。
6. 不要做 CarPlay。
7. 不要重构已经完成的播放内核。
8. 不要大改 UI 风格。
9. 不要把 sid/synotoken 放到 UserDefaults。
10. 不要保存明文密码。
