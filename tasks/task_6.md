基于当前 NASMusic 项目继续开发。

目标：实现 Synology Audio Station 封面加载、本地缓存、播放器封面联动。

当前状态：

1. SwiftUI Mock UI 已完成。
2. PlaybackManager 已完成。
3. 后台播放、锁屏控制、控制中心播放信息已完成。
4. NAS 连接配置、DSM 登录、Keychain 凭证保存已完成。
5. Audio Station 音乐库列表已完成。
6. 点击真实 NAS 歌曲可以播放。
7. 当前封面仍然是 Mock 图或占位图。

本阶段任务：

一、扩展音乐模型

检查并扩展 Song / Album / Playlist 模型。

Song 增加或确认以下字段：

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

Album 增加或确认：

struct Album: Identifiable, Equatable, Codable {
let id: String
let title: String
let artist: String?
let year: Int?
let songCount: Int?
let coverId: String?
let source: MusicSource
}

要求：

1. coverId 只保存 Audio Station 返回的封面标识。
2. 不要把带 sid 的完整封面 URL 持久化。
3. 不要把封面二进制数据放进 Song / Album 模型。
4. Mock 数据继续支持本地图片或远程图片。

二、新增封面 Provider 抽象

新增：

Core/Music/ArtworkProvider.swift

定义协议：

protocol ArtworkProvider {
func fetchArtworkData(coverId: String, size: ArtworkSize) async throws -> Data
func fetchArtworkImage(coverId: String, size: ArtworkSize) async throws -> UIImage
}

新增：

enum ArtworkSize: String, Codable {
case thumbnail
case medium
case large
}

实现两个 Provider：

1. MockArtworkProvider

   * 用于 Mock 数据和 SwiftUI Preview。
   * 返回本地默认封面或测试图片。

2. SynologyArtworkProvider

   * 通过 Audio Station API 获取真实封面。
   * 依赖 NASSessionManager、SynologyAPIClient、Keychain 凭证。

三、实现 Audio Station 封面接口

在 SynologyAudioStationProvider 或单独 SynologyArtworkProvider 中实现封面 URL 构造和请求。

优先通过 API Discovery 查询以下 API：

1. SYNO.AudioStation.Cover
2. SYNO.AudioStation.Song
3. SYNO.AudioStation.Album

如果 SYNO.AudioStation.Cover 存在，优先使用它。

建议实现方式：

GET /webapi/<discovered-path>
?api=SYNO.AudioStation.Cover
&version=<maxVersion>
&method=getcover
&id=<coverId>
&size=<thumbnail|medium|large>
&_sid=<sid>

注意：

1. path 和 version 必须来自 SYNO.API.Info。
2. 如果某个 DSM / Audio Station 版本的 method 或参数不同，需要在代码中保留兼容分支。
3. 如果接口返回的是图片二进制，直接解析 Data。
4. 如果接口返回 JSON 错误，需要解析 success/error.code。
5. 如果 coverId 为空，直接返回默认封面，不要发网络请求。
6. 不打印完整封面 URL，因为 URL 中可能带 _sid。
7. 不持久化带鉴权参数的 URL。

四、实现封面缓存系统

新增：

Core/Cache/ArtworkMemoryCache.swift
Core/Cache/ArtworkDiskCache.swift
Core/Cache/ArtworkCacheManager.swift

缓存策略：

1. 内存缓存：

   * 使用 NSCache。
   * key = nasId + coverId + size。
   * value = UIImage。
   * 限制总数量，例如 300 张。
   * iOS 内存压力时允许系统自动清理。

2. 磁盘缓存：

   * 路径：Application Support/NASMusic/ArtworkCache/
   * key 使用 SHA256(nasId + coverId + size) 生成文件名。
   * 文件格式优先保存 JPEG 或原始 Data。
   * 保存时不要把 sid / synotoken 写进文件名。
   * 默认最大缓存容量 500MB。
   * 超出容量后按最后访问时间清理旧文件。
   * 支持 clearArtworkCache()。

3. 缓存读取顺序：

   * 先读内存缓存。
   * 再读磁盘缓存。
   * 最后请求网络。
   * 网络成功后同时写入内存和磁盘。

五、实现图片加载器

新增：

Core/ImageLoading/ArtworkImageLoader.swift

职责：

1. 根据 coverId 和 size 加载图片。
2. 内部调用 ArtworkCacheManager。
3. 支持 async/await。
4. 支持取消任务。
5. 避免列表滚动时重复请求同一个 coverId。
6. 同一个 coverId + size 正在请求时，后续调用复用同一个 Task。
7. 网络失败时返回默认占位图。
8. 图片解码时做 downsample，避免大图占用过多内存。

建议暴露：

@MainActor
final class ArtworkImageViewModel: ObservableObject {
@Published var image: UIImage?
@Published var isLoading: Bool = false
@Published var errorMessage: String?

```
func load(coverId: String?, size: ArtworkSize)
func cancel()
```

}

六、新增 SwiftUI 封面组件

新增：

Shared/Components/ArtworkView.swift

功能：

1. 输入 coverId、size、cornerRadius。
2. 自动加载图片。
3. 加载中显示 skeleton 或灰色占位。
4. 失败时显示默认封面。
5. 支持列表小图、专辑中图、播放器大图三种尺寸。
6. 支持 SwiftUI Preview。
7. 不要在每个页面重复写加载逻辑。

示例使用：

ArtworkView(
coverId: song.coverId,
size: .thumbnail,
cornerRadius: 8
)

七、接入页面

修改以下页面：

1. HomeView

   * 最近添加显示真实封面。
   * 推荐区域如果是真实歌曲，也显示封面。
   * NAS 状态卡片不受影响。

2. LibraryView / SongListView

   * 每首歌左侧显示 thumbnail 封面。
   * 无封面时显示默认音乐图标。
   * 滚动时不能明显卡顿。

3. AlbumListView

   * 专辑卡片显示 medium 封面。
   * 无封面时使用默认专辑图。

4. AlbumDetailView

   * 顶部显示 large 专辑封面。
   * 歌曲列表可继续显示小封面或复用专辑封面。

5. PlayerView

   * 播放器大页显示 large 封面。
   * 切歌时封面同步切换。
   * 加载新封面时不要闪白屏，可以先显示旧封面或占位图。

6. MiniPlayerView

   * 左侧显示当前歌曲 thumbnail 封面。

八、锁屏 Now Playing 封面联动

修改 NowPlayingInfoManager。

要求：

1. 当前歌曲有 coverId 时，异步加载 medium 或 large 封面。
2. 加载成功后设置 MPMediaItemArtwork。
3. 播放歌曲切换时更新锁屏封面。
4. 如果封面加载慢，先显示歌曲名/歌手，封面加载完成后再刷新 artwork。
5. 如果封面加载失败，使用默认 App 图标或默认封面。
6. 不要因为封面加载失败影响播放。
7. 避免旧歌曲封面异步返回后覆盖新歌曲封面。

九、设置页增加缓存管理

在 Settings 页面增加“缓存管理”区域：

展示：

1. 封面缓存大小。
2. 封面缓存文件数量。

操作：

1. 清除封面缓存。
2. 清除后 UI 立即刷新缓存大小。
3. 清除过程有 loading 状态。
4. 清除失败时显示错误。

不要在本阶段做音频离线缓存，只处理封面缓存。

十、错误处理

新增 ArtworkError：

enum ArtworkError: LocalizedError {
case missingCoverId
case apiUnavailable
case sessionExpired
case invalidImageData
case networkError(Error)
case diskWriteFailed
case diskReadFailed
case unknown
}

用户侧提示：

1. 列表页不要弹大量错误 toast。
2. 封面失败时静默显示默认封面。
3. 设置页清理缓存失败时再显示明确错误。
4. Debug 日志可以记录错误，但不能打印 sid/synotoken/完整 URL。

十一、性能要求

1. 歌曲列表滚动 100 条数据时不能明显掉帧。
2. 同一封面不能重复发起大量请求。
3. 列表图片使用 thumbnail。
4. 播放器大页使用 large。
5. 锁屏 artwork 使用 medium 或 large。
6. 图片写入磁盘前可做压缩。
7. 后台线程处理磁盘 IO 和图片解码。
8. 主线程只做 UI 更新。
9. App 进入后台时不要继续批量预加载封面。
10. 内存警告时清理内存缓存。

十二、安全要求

1. 不打印 password。
2. 不打印 sid。
3. 不打印 synotoken。
4. 不打印完整封面 URL。
5. 磁盘缓存文件名不能包含 NAS 地址、用户名、sid、synotoken。
6. 只使用 hash key 作为缓存文件名。

十三、不要做的事情

1. 不要做音频离线下载。
2. 不要做歌词。
3. 不要做 QuickConnect。
4. 不要做 Bonjour 自动发现。
5. 不要做 CarPlay。
6. 不要做本地音乐数据库。
7. 不要大改现有 UI 风格。
8. 不要重构已经完成的播放内核。
9. 不要把封面 URL 保存进 UserDefaults。
10. 不要保存任何带鉴权参数的 URL。

