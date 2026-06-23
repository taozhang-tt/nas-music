# 第 7.3 步：真实歌曲写回验收与产品化收口

## 当前状态

已完成真实歌曲写回产品化收口：

1. 写入按钮只在远程 metadata 已加载、格式支持写回、有实际变化且未写入中时可用。
2. 编辑页新增“重新读取”，写入成功后会自动重新读取 Agent metadata。
3. 空变更不会写入，并显示“没有检测到标签变化”。
4. 只通过“转换为简体”产生的预览变化会写入 preview 后结果。
5. 写入成功文案明确区分“NAS 文件已写入 / App 本地已更新 / 群晖索引等待刷新”。
6. 不支持格式、未建立索引、认证失败、路径拒绝等错误文案已统一。
7. 设置页测试 FLAC 入口已改为 DEBUG-only 诊断入口。
8. 已通过真实 FLAC 歌曲验收：读取、预览、写入临时标题、重新读取、改回原值。
9. 已验证：`go test ./...` 通过，iOS `xcodebuild` 构建通过。

## 一、背景

第 7.1 步完成了 NASMusic Agent 与测试 FLAC 写回闭环。

第 7.2 步完成了真实歌曲索引接入：

1. Audio Station song list 可以返回真实 path。
2. iOS 同步音乐库时会把 `sourceId -> path` 推送给 Agent。
3. Agent 已验证接收真实索引：`accepted=8 rejected=0 songCount=9`。
4. 真实歌曲入口已经可以调用现有写回 API。

当前还缺少的是：

1. 从真实歌曲入口完整验收“读标签 -> 预览 -> 写入 -> 重新读取 -> 改回原值”。
2. 不支持格式的 UI 禁用与明确提示。
3. Debug 测试入口需要降级，不应成为正式主路径。
4. 写入后状态需要更清楚地区分“本地已更新”和“群晖索引待刷新”。

## 二、目标

把标签写回从“真实索引已打通”推进到“真实歌曲写回可放心使用”。

完成后：

1. 用户可以从真实 NAS 歌曲进入标签编辑页。
2. 支持写回的真实 FLAC/MP3 可以完成读取、预览、写入和重新读取验证。
3. 不支持格式不能写入，并显示明确原因。
4. 写入成功后 UI 不误导用户，以清晰状态提示群晖索引刷新可能滞后。
5. 设置页 Debug 测试入口被隐藏、折叠或标注为诊断用途。

## 三、范围

本阶段做：

1. 真实歌曲写回主路径验收。
2. 编辑页支持/不支持格式的状态收口。
3. 写入按钮禁用规则完善。
4. 写入后状态文案完善。
5. Debug 测试入口收口。
6. 错误信息映射和 UI 文案整理。

本阶段暂不做：

1. 批量写回。
2. M4A/ALAC/AAC/OGG/Opus 等更多格式写入。
3. 完整 OpenCC 接入。
4. 自动触发 Audio Station 重新索引。
5. HTTPS / 证书 / 反向代理自动化。

## 四、真实歌曲写回主路径

从 Library 真实歌曲列表开始：

```text
真实歌曲长按 / 右键
  -> 编辑 NAS 标签
  -> 读取 Agent metadata
  -> 生成预览
  -> 写入 NAS 文件
  -> 重新读取 Agent metadata
  -> 确认新标签
  -> 改回原值
```

要求：

1. 入口只对 `.synology` 歌曲显示或启用。
2. Agent 未启用时，入口禁用或显示“请先启用 NASMusic Agent”。
3. 歌曲未建立索引时，显示“Agent 尚未建立这首歌的文件索引，请先同步音乐库”。
4. Agent 返回 metadata 后，必须展示：
   - 格式
   - 文件大小
   - 最后修改时间
   - 是否支持写回
   - revision
5. 写入成功后必须允许重新加载远程 metadata。

## 五、不支持格式 UI

Agent 第一版安全写回格式：

1. FLAC
2. MP3

如果 Agent 返回：

```http
415 Unsupported Media Type
```

UI 必须：

1. 显示“当前格式暂不支持安全修改标签。”
2. 禁用“写入 NAS 文件”按钮。
3. 允许用户查看只读 metadata。
4. 不显示会误导用户可以写入的成功状态。

未来支持格式再逐步开放：

1. M4A / MP4 / ALAC / AAC
2. OGG Vorbis
3. Opus
4. WAV / AIFF
5. APE / WMA / DSF 等

## 六、写入按钮规则

“写入 NAS 文件”按钮只有在以下条件同时满足时可用：

1. 已成功加载远程 metadata。
2. `writeSupported == true`。
3. 当前没有写入任务。
4. Agent 已配置并启用。
5. 当前歌曲有 `audioStationId`。
6. 当前 patch 非空，或者“转换为简体”预览产生了变化。

如果 patch 为空且没有转换变化：

```text
没有检测到标签变化。
```

不要执行空写入。

## 七、写入后状态

写入成功后显示：

```text
文件已写入 NAS，App 已更新本地标签，等待群晖音乐索引刷新。
```

同时：

1. 更新本地数据库。
2. 记录 `metadata_write_operations`。
3. `metadata_write_status` 设置为 `waitingForIndex` 或 `indexed`。
4. 编辑页提供“重新读取”按钮，重新从 Agent 读取真实文件 metadata。

不要显示：

```text
Audio Station 已更新
```

除非后续真的实现并验证了 Audio Station 索引刷新检测。

## 八、Debug 测试入口收口

设置页当前有：

```text
编辑 Agent 测试 FLAC
```

处理方案任选其一：

### 方案 A：Debug-only

仅在 `#if DEBUG` 下显示。

### 方案 B：折叠到诊断区

放入“Agent 诊断”折叠区，避免普通用户误以为这是主入口。

### 方案 C：保留但加说明

显示为：

```text
诊断：编辑测试 FLAC
```

推荐方案 A 或 B。

## 九、错误文案

统一错误文案：

| 场景 | UI 文案 |
| --- | --- |
| 401 / 403 | Agent 认证失败，请检查 API Token。 |
| 404 songNotFound | Agent 尚未建立这首歌的文件索引，请先同步音乐库。 |
| 409 fileChanged | 该音乐文件已被其他程序修改，请重新加载后再保存。 |
| 415 unsupportedFormat | 当前格式暂不支持安全修改标签。 |
| 423 fileLocked | 该音乐文件正在被其他写入任务处理，请稍后重试。 |
| pathNotAllowed | Agent 拒绝访问该音乐文件路径，请检查索引和 musicRoots 配置。 |
| agentUnavailable | 无法连接 NASMusic Agent，请检查服务状态和网络。 |
| invalidResponse | NASMusic Agent 返回了无法识别的响应。 |

## 十、验收标准

### 真实 FLAC

1. 从真实 FLAC 歌曲入口进入编辑页。
2. 成功读取 metadata。
3. 成功生成预览。
4. 修改 title 为临时值。
5. 成功写入 NAS 文件。
6. 重新读取 Agent metadata 显示临时值。
7. 改回原值并再次写入成功。
8. 本地列表显示新标签。

### 真实 MP3

1. 如果有真实 MP3，重复 FLAC 验收。
2. 如果暂时没有 MP3，使用测试 MP3 文件补充。

### 不支持格式

1. 选择一个不支持格式。
2. 编辑页显示格式不支持。
3. 写入按钮禁用。
4. 不会发起 PATCH 写入请求。

### 错误场景

1. 停止 Agent，App 显示连接失败。
2. 修改错误 token，App 显示认证失败。
3. 清空某首歌索引，App 显示未建立索引。
4. 使用旧 revision 写入，App 显示文件已变化。

## 十一、测试计划

1. 运行 `go test ./...`。
2. 运行 iOS `xcodebuild` 构建。
3. NAS 上确认 Agent 运行：

```sh
~/nasmusic-agentctl.sh status
```

4. App 设置页检查 Agent 状态，确认索引歌曲数大于 1。
5. 真实 FLAC 写入验收。
6. 不支持格式验收。
7. 检查日志不泄漏：
   - password
   - sid
   - synotoken
   - API token
   - 带鉴权 query 的完整 URL

## 十二、完成后再考虑

完成 7.3 后，再进入后续任务：

1. 7.4：更多格式写入支持。
2. 7.5：完整 OpenCC 集成与字段选择。
3. 7.6：Audio Station 索引刷新检测。
4. 7.7：批量标签写回。
