# 第 7.2 步：将标签写回接入真实 NAS 歌曲

## 当前状态

已实现第一版真实歌曲索引接入：

1. iOS `Song` 已保留 Audio Station 返回的 `path` 字段，并写入本地数据库 `songs.path`。
2. iOS 同步音乐库时，会把带 path 的真实歌曲批量同步给 NASMusic Agent。
3. Agent 新增 `PUT /v1/library/index`，只接受 token 鉴权后的受控索引更新。
4. Agent 更新索引时继续校验 path 必须位于 `musicRoots` 内，并使用临时文件 + rename 原子写入。
5. Agent 新增 `GET /v1/library/index/status`，设置页会显示索引歌曲数和更新时间。
6. Library 真实 NAS 歌曲的“编辑 NAS 标签”入口继续使用现有写回 API，不向写回 API 传 path。
7. 已验证：Audio Station 返回真实 path，`pathCount=8`。
8. 已验证：Agent 接收真实索引，`accepted=8 rejected=0 songCount=9`。
9. 已验证：`go test ./...` 通过，iOS `xcodebuild` 构建通过。

## 一、背景

第 7.1 步已经完成并验证了第一版写回闭环：

1. iOS App 可以配置 NASMusic Agent。
2. Agent 可以读取、预览、写入并备份 NAS 上的测试 FLAC 文件。
3. App 可以通过 `http://sh.zero-tt.top:2302` 直连 Agent。
4. Synology 上已经有服务化部署脚本，支持后台启动、停止和重启。

当前限制是：

1. iOS 主要通过 Debug 入口“编辑 Agent 测试 FLAC”验证写回。
2. Agent 的 `library-index.json` 当前只包含 `test-flac`。
3. 真实 Audio Station 歌曲还没有稳定映射到 NAS 文件路径。

本阶段目标是把写回从“测试闭环”推进到“真实歌曲可用”。

## 二、目标

让用户可以从真实 NAS 歌曲进入标签编辑页，并把修改写回该歌曲对应的 NAS 原始音频文件。

完成后：

1. Library 中真实 NAS 歌曲可以进入“编辑标签”。
2. App 传给 Agent 的 `sourceId` 可以稳定映射到真实音频文件。
3. Agent 不接受 App 传任意文件路径。
4. 写入前仍然执行 revision 冲突检测、备份、校验和原子替换。
5. 不支持写回的文件格式必须明确提示，不允许误写。
6. 写入成功后，本地 UI 和数据库显示最新标签。
7. 群晖索引尚未刷新时，UI 显示“等待群晖索引刷新”。

## 三、范围

本阶段做：

1. 真实歌曲编辑入口。
2. 真实 `sourceId -> path` 索引生成或维护。
3. iOS 与 Agent 对真实歌曲的写回联调。
4. 写回后的本地状态更新和提示。
5. 不支持格式的明确 UI。

本阶段暂不做：

1. 批量写回。
2. 完整 OpenCC 集成。
3. 自动触发群晖 Audio Station 重新索引。
4. M4A、OGG、Opus 等更多格式写入。
5. 多用户权限模型。
6. 公网 HTTPS / 证书部署自动化。

## 四、核心问题：真实歌曲如何映射文件路径

iOS App 不能直接传 NAS 文件路径给 Agent。

Agent 必须使用受控索引：

```text
sourceId -> absolute file path
```

其中：

```text
sourceId = Audio Station song id 或 NASMusic 内部稳定 id
path     = /volume2/music/.../song.flac
```

路径必须满足：

1. 位于 `musicRoots` 配置的允许目录下。
2. 解析符号链接后仍位于允许目录下。
3. 不允许 `../` 越界。
4. 不允许 App 请求时提交 path。

## 五、候选方案

### 方案 A：Agent 扫描音乐目录生成索引

Agent 启动或手动命令扫描 `/volume2/music`，读取所有音频文件，生成：

```json
{
  "songs": [
    {
      "sourceId": "...",
      "path": "/volume2/music/..."
    }
  ]
}
```

问题：

1. 文件系统本身没有 Audio Station song id。
2. 只能基于文件路径、文件名、标签、大小、mtime 生成内部 id。
3. iOS 同步到的 Audio Station id 不一定能匹配。

适合：

1. 未来完全脱离 Audio Station 做自己的音乐库索引。

### 方案 B：从 Audio Station API 获取文件路径

如果 Audio Station 的歌曲详情 API 可以返回真实文件路径或可反推路径，则 iOS 同步时保存该字段，并把 `sourceId -> path` 同步给 Agent。

优点：

1. `sourceId` 与当前 Audio Station 歌曲 id 一致。
2. 用户从真实歌曲进入编辑页时映射稳定。

风险：

1. Audio Station API 可能不返回真实路径。
2. 不同 DSM / Audio Station 版本字段可能不一致。
3. 需要确认是否会泄漏路径到日志或 UI。

### 方案 C：iOS 维护受控索引，Agent 只接受签名/鉴权后的索引更新

新增 Agent API：

```http
PUT /v1/library/index
```

请求：

```json
{
  "songs": [
    {
      "sourceId": "12345",
      "path": "/volume2/music/artist/song.flac",
      "title": "歌曲名",
      "artist": "歌手",
      "fileSize": 12345678,
      "modifiedAt": "2026-06-23T10:00:00Z"
    }
  ]
}
```

Agent 处理：

1. token 鉴权。
2. 校验每个 path 在 `musicRoots` 内。
3. 原子写入 `library-index.json`。
4. 返回成功数量、拒绝数量和拒绝原因。

优点：

1. iOS 同步真实歌曲后，可以同步索引给 Agent。
2. Agent 仍然不在写回 API 中接受任意 path。
3. 后续可以做增量更新。

风险：

1. 前提是 iOS 能拿到真实 path。
2. 如果 path 获取不到，仍无法完成真实歌曲写回。

## 六、推荐推进方式

先做一个探针任务：

1. 检查当前 Synology Audio Station song list/detail API 是否返回 path 或可用于定位文件的字段。
2. 对真实歌曲打印安全诊断字段：
   - song id
   - title
   - artist
   - album
   - file extension
   - 是否存在 path 字段
   - path 所在 JSON key 名称
3. 不打印 sid、token、password。
4. 不打印完整私密 URL。

如果能拿到 path：

1. 实现方案 C 的 `PUT /v1/library/index`。
2. iOS 同步后把 sourceId/path 更新给 Agent。
3. 真实歌曲编辑页调用现有写回 API。

如果拿不到 path：

1. 暂停真实写回入口。
2. 设计 Agent 自建音乐库索引方案。
3. iOS 侧需要从 Agent 音乐库而不是 Audio Station 音乐库进入写回。

## 七、iOS 改造

### 1. 真实歌曲入口

在真实 NAS 歌曲的更多操作中增加：

```text
编辑 NAS 标签
```

显示条件：

1. 当前歌曲来源是 `.synology`。
2. Metadata Writeback 已启用。
3. Agent health 正常。

如果不满足，显示灰色入口或明确提示：

```text
请先在设置中启用 NASMusic Agent。
```

### 2. 编辑页加载

进入编辑页后：

1. 使用真实 `audioStationId` 作为 sourceId。
2. 调用：

```http
GET /v1/songs/{sourceId}/metadata
```

如果 Agent 返回 404：

```text
Agent 尚未建立这首歌的文件索引，请先同步 NAS 文件索引。
```

如果返回 415：

```text
当前格式暂不支持安全写回。
```

### 3. 写入后状态

写入成功后：

1. 更新本地歌曲标签。
2. 保存 write operation 记录。
3. 显示：

```text
文件已写入 NAS，等待群晖音乐索引刷新。
```

不让 UI 假装 Audio Station 已立即刷新。

## 八、Agent 改造

### 1. 索引更新 API

新增：

```http
PUT /v1/library/index
```

或更保守：

```http
POST /v1/library/index/songs
```

要求：

1. token 鉴权。
2. 校验 path 在 musicRoots 下。
3. 对每条记录返回 accepted/rejected。
4. 写入时使用临时文件 + rename。
5. 不因为单条失败导致整批失败，除非请求 JSON 无效。

### 2. 索引状态 API

新增：

```http
GET /v1/library/index/status
```

响应：

```json
{
  "songCount": 1234,
  "updatedAt": "2026-06-23T10:00:00Z",
  "missingPathCount": 0
}
```

### 3. 日志安全

日志中禁止出现：

1. password
2. sid
3. synotoken
4. API token
5. 带鉴权 query 的完整 URL

路径日志可以在 Debug 下打印，但默认只打印：

```text
sourceId
extension
path basename
```

## 九、格式支持策略

当前第一版安全写回：

1. FLAC
2. MP3

真实歌曲如果是：

1. m4a
2. alac
3. aac
4. ogg
5. opus
6. wav
7. ape
8. dsf

必须显示：

```text
当前格式暂不支持安全修改标签。
```

不要提供写入按钮。

## 十、验收标准

### Agent

1. `GET /v1/health` 正常。
2. `GET /v1/library/index/status` 返回真实索引数量。
3. `PUT /v1/library/index` 可以新增或更新真实歌曲映射。
4. 非 musicRoots 路径被拒绝。
5. 路径穿越被拒绝。
6. 索引文件写入为原子操作。
7. 不支持格式返回 415。

### iOS

1. 真实 NAS 歌曲可以进入标签编辑页。
2. 未建立索引的歌曲显示明确错误。
3. 已建立索引的 FLAC 歌曲可以读取标签。
4. 已建立索引的 FLAC 歌曲可以生成预览。
5. 已建立索引的 FLAC 歌曲可以写回。
6. 写回后重新读取 Agent metadata 显示新标签。
7. 本地 UI 显示新标签。
8. Audio Station 索引未刷新时 UI 不误导用户。

### 安全

1. App 不传任意 path 给写回 API。
2. Agent 不写 musicRoots 外文件。
3. revision 冲突返回 409。
4. token 错误返回 401/403。
5. 日志不泄漏 token、sid、password。

## 十一、测试计划

1. 使用 `/volume2/music/.nasmusic-agent-test/test.flac` 验证兼容旧测试入口。
2. 选择一首真实 FLAC 歌曲建立索引。
3. 从 App 真实歌曲入口进入编辑页。
4. 修改 title 为临时值。
5. 写回成功后重新读取 Agent metadata。
6. 再改回原值。
7. 对一首不支持格式歌曲确认 UI 禁止写入。
8. 构造非法路径索引，确认 Agent 拒绝。
9. 构造旧 revision 写入，确认 409。

## 十二、开放问题

1. Audio Station API 是否能返回真实文件路径？
2. 如果不能返回路径，是否接受 Agent 自建音乐库索引并逐步替代 Audio Station 音乐库？
3. 真实路径是否允许显示在 Debug 日志里？
4. 索引更新应该由 iOS 触发，还是由 NAS Agent 自己扫描？
5. 是否需要在 Synology DSM 中做计划任务，定期重建索引？
