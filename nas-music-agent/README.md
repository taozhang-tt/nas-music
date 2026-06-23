# NASMusic Agent

NASMusic Agent is the NAS-side HTTP service for audio metadata writeback.

Current status:

- Implements the API shape for health, metadata read, preview, write, and rollback.
- Enforces Bearer token authentication for non-health endpoints.
- Rejects path traversal and never accepts absolute file paths from the iOS client.
- Resolves songs from a configured `sourceId` index file.
- Supports real MP3 ID3v2.4 and FLAC Vorbis Comment text metadata read/write without audio re-encoding.
- Returns safe `415 Unsupported Media Type` for formats that do not have a writer yet.
- Supports a small built-in Traditional-to-Simplified preview mapping for common fields; wire real OpenCC before broad production use.

Configuration file:

Put `nasmusic-agent.json` next to the binary, for example `/var/services/homes/admin/nasmusic-agent.json`.
The agent automatically loads `nasmusic-agent.json` from the current directory or from the binary directory.

```json
{
  "listenAddr": "0.0.0.0:2302",
  "apiToken": "change-me",
  "musicRoots": ["/volume2/music"],
  "libraryIndex": "/var/services/homes/admin/nasmusic-agent-test/library-index.json",
  "backupDir": "/var/services/homes/admin/nasmusic-agent-test/backup"
}
```

Start on the NAS:

```sh
chmod 600 /var/services/homes/admin/nasmusic-agent.json
chmod +x /var/services/homes/admin/nasmusic-agent
/var/services/homes/admin/nasmusic-agent
```

Synology service layout:

```sh
~/nasmusic-agentctl.sh start
```

By default the control script creates this service directory:

```text
~/nasmusic-agent-service/
├── backup/
├── bin/
│   └── nasmusic-agent
├── data/
│   └── library-index.json
├── etc/
│   └── nasmusic-agent.json
├── logs/
│   └── nasmusic-agent.log
└── run/
    └── nasmusic-agent.pid
```

The control script:

- Reads `TOKEN=...` or `NASMUSIC_AGENT_TOKEN=...` from `~/nasmusic-agent-test/env`.
- Copies `~/nasmusic-agent` into `~/nasmusic-agent-service/bin/nasmusic-agent`.
- Writes the complete config to `~/nasmusic-agent-service/etc/nasmusic-agent.json`.
- Creates the test `library-index.json` for `test-flac` when it is missing.
- Starts the agent in the background with `nohup`.
- Writes logs to `~/nasmusic-agent-service/logs/nasmusic-agent.log`.

Service commands:

```sh
~/nasmusic-agentctl.sh install
~/nasmusic-agentctl.sh start
~/nasmusic-agentctl.sh status
~/nasmusic-agentctl.sh logs
~/nasmusic-agentctl.sh stop
~/nasmusic-agentctl.sh restart
```

You can also pass an explicit config path:

```sh
/var/services/homes/admin/nasmusic-agent -config /var/services/homes/admin/nasmusic-agent.json
```

Index format:

```json
{
  "songs": [
    {
      "sourceId": "12345",
      "path": "/volume1/music/artist/album/song.mp3"
    }
  ]
}
```

Required production work before enabling real writes:

- Extend the writer with TagLib-backed metadata read/write for M4A, OGG, Opus, and other production formats.
- Add full OpenCC conversion.
- Move operation records and backup manifests from JSON files to a durable store if higher queryability is needed.
- Serve HTTPS on the NAS or place the service behind a trusted HTTPS reverse proxy.

Direct iOS app integration:

1. Start the agent on the NAS with `listenAddr` set to `0.0.0.0:2302`.
2. In NASMusic Settings, enable metadata writeback, set the Agent URL to `http://sh.zero-tt.top:2302`, paste the API token, and run the Agent health check.
3. Use the debug entry "编辑 Agent 测试 FLAC" with a library index entry whose `sourceId` is `test-flac`.
4. Sync the iOS music library to push real `sourceId -> path` mappings to the Agent.
5. Use the real-song "编辑 NAS 标签" entry from the library song context menu.

Library index APIs:

```http
GET /v1/library/index/status
PUT /v1/library/index
```

`PUT /v1/library/index` accepts authenticated, controlled `sourceId -> path` mappings. The Agent validates every path against `musicRoots` and writes `library-index.json` atomically; writeback APIs still never accept arbitrary paths from the iOS app.

Simulator tunnel fallback:

1. Start the agent on the NAS bound to loopback, for example `NASMUSIC_AGENT_ADDR=127.0.0.1:8088`.
2. Open a local tunnel from the Mac:

   ```sh
   ssh -p 2322 -L 8088:127.0.0.1:8088 admin@sh.zero-tt.top
   ```

3. In NASMusic Settings, enable metadata writeback, set the Agent URL to `http://127.0.0.1:8088`, paste the API token, and run the Agent health check.
4. Use the debug entry "编辑 Agent 测试 FLAC" with a library index entry whose `sourceId` is `test-flac`.
