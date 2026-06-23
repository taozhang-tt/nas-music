#!/bin/sh
set -eu

SERVICE_DIR="${NASMUSIC_AGENT_SERVICE_DIR:-$HOME/nasmusic-agent-service}"
BIN_DIR="$SERVICE_DIR/bin"
ETC_DIR="$SERVICE_DIR/etc"
DATA_DIR="$SERVICE_DIR/data"
LOG_DIR="$SERVICE_DIR/logs"
RUN_DIR="$SERVICE_DIR/run"
BACKUP_DIR="${NASMUSIC_BACKUP_DIR:-$SERVICE_DIR/backup}"

AGENT_BIN="$BIN_DIR/nasmusic-agent"
CONFIG_PATH="$ETC_DIR/nasmusic-agent.json"
PID_FILE="$RUN_DIR/nasmusic-agent.pid"
LOG_FILE="$LOG_DIR/nasmusic-agent.log"

SOURCE_BIN="${NASMUSIC_AGENT_SOURCE_BIN:-$HOME/nasmusic-agent}"
ENV_FILE="${NASMUSIC_AGENT_ENV:-$HOME/nasmusic-agent-test/env}"
LISTEN_ADDR="${NASMUSIC_AGENT_LISTEN_ADDR:-0.0.0.0:2302}"
MUSIC_ROOT="${NASMUSIC_MUSIC_ROOT:-/volume2/music}"
LIBRARY_INDEX="${NASMUSIC_LIBRARY_INDEX:-$DATA_DIR/library-index.json}"
TEST_FILE="${NASMUSIC_TEST_FILE:-$MUSIC_ROOT/.nasmusic-agent-test/test.flac}"

usage() {
	cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  install   Create service directory, config, index, and copy binary
  start     Start NASMusic Agent in background
  stop      Stop NASMusic Agent
  restart   Restart NASMusic Agent
  status    Show service status
  logs      Follow service log

Environment overrides:
  NASMUSIC_AGENT_SERVICE_DIR  default: $HOME/nasmusic-agent-service
  NASMUSIC_AGENT_SOURCE_BIN   default: $HOME/nasmusic-agent
  NASMUSIC_AGENT_ENV          default: $HOME/nasmusic-agent-test/env
  NASMUSIC_AGENT_LISTEN_ADDR  default: 0.0.0.0:2302
  NASMUSIC_MUSIC_ROOT         default: /volume2/music
EOF
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

load_token() {
	if [ -n "${NASMUSIC_AGENT_TOKEN:-}" ]; then
		return
	fi
	if [ -f "$ENV_FILE" ]; then
		# shellcheck disable=SC1090
		. "$ENV_FILE"
		if [ -n "${TOKEN:-}" ]; then
			NASMUSIC_AGENT_TOKEN="$TOKEN"
		fi
	fi
	if [ -z "${NASMUSIC_AGENT_TOKEN:-}" ]; then
		echo "NASMUSIC_AGENT_TOKEN is required. Put TOKEN=... or NASMUSIC_AGENT_TOKEN=... in $ENV_FILE." >&2
		exit 1
	fi
}

is_running() {
	if [ ! -f "$PID_FILE" ]; then
		return 1
	fi
	pid="$(cat "$PID_FILE" 2>/dev/null || true)"
	if [ -z "$pid" ]; then
		return 1
	fi
	kill -0 "$pid" 2>/dev/null
}

install_service() {
	load_token
	mkdir -p "$BIN_DIR" "$ETC_DIR" "$DATA_DIR" "$LOG_DIR" "$RUN_DIR" "$BACKUP_DIR"

	if [ ! -x "$AGENT_BIN" ]; then
		if [ ! -f "$SOURCE_BIN" ]; then
			echo "Agent binary not found: $SOURCE_BIN" >&2
			exit 1
		fi
		cp "$SOURCE_BIN" "$AGENT_BIN"
		chmod +x "$AGENT_BIN"
	fi

	if [ ! -f "$LIBRARY_INDEX" ]; then
		if [ ! -f "$TEST_FILE" ]; then
			echo "Library index is missing and test file was not found: $TEST_FILE" >&2
			exit 1
		fi
		cat > "$LIBRARY_INDEX" <<EOF
{
  "songs": [
    {
      "sourceId": "test-flac",
      "path": "$(json_escape "$TEST_FILE")"
    }
  ]
}
EOF
		chmod 600 "$LIBRARY_INDEX"
	fi

	umask 077
	cat > "$CONFIG_PATH" <<EOF
{
  "listenAddr": "$(json_escape "$LISTEN_ADDR")",
  "apiToken": "$(json_escape "$NASMUSIC_AGENT_TOKEN")",
  "musicRoots": ["$(json_escape "$MUSIC_ROOT")"],
  "libraryIndex": "$(json_escape "$LIBRARY_INDEX")",
  "backupDir": "$(json_escape "$BACKUP_DIR")"
}
EOF
	chmod 600 "$CONFIG_PATH"

	echo "Installed NASMusic Agent service:"
	echo "  serviceDir: $SERVICE_DIR"
	echo "  binary:     $AGENT_BIN"
	echo "  config:     $CONFIG_PATH"
	echo "  log:        $LOG_FILE"
}

start_service() {
	install_service
	if is_running; then
		echo "NASMusic Agent is already running, pid $(cat "$PID_FILE")."
		return
	fi
	nohup "$AGENT_BIN" -config "$CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
	echo "$!" > "$PID_FILE"
	sleep 1
	if is_running; then
		echo "NASMusic Agent started, pid $(cat "$PID_FILE")."
		echo "Log: $LOG_FILE"
	else
		echo "NASMusic Agent failed to start. Last log lines:" >&2
		tail -50 "$LOG_FILE" >&2 || true
		exit 1
	fi
}

stop_service() {
	if ! is_running; then
		rm -f "$PID_FILE"
		echo "NASMusic Agent is not running."
		return
	fi
	pid="$(cat "$PID_FILE")"
	kill "$pid"
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		if ! kill -0 "$pid" 2>/dev/null; then
			rm -f "$PID_FILE"
			echo "NASMusic Agent stopped."
			return
		fi
		sleep 1
	done
	kill -9 "$pid" 2>/dev/null || true
	rm -f "$PID_FILE"
	echo "NASMusic Agent force stopped."
}

status_service() {
	if is_running; then
		echo "NASMusic Agent running, pid $(cat "$PID_FILE")."
		echo "Config: $CONFIG_PATH"
		echo "Log:    $LOG_FILE"
	else
		echo "NASMusic Agent is not running."
	fi
}

case "${1:-}" in
	install)
		install_service
		;;
	start)
		start_service
		;;
	stop)
		stop_service
		;;
	restart)
		stop_service
		start_service
		;;
	status)
		status_service
		;;
	logs)
		tail -f "$LOG_FILE"
		;;
	*)
		usage
		exit 1
		;;
esac
