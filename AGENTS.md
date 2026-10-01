# AGENTS.md

Go 1.26+ proxy server providing OpenAI/Gemini/Claude/Codex compatible APIs with OAuth and round-robin load balancing.

## Repository
- GitHub: https://github.com/router-for-me/CLIProxyAPI
- This checkout is a personal fork with local-only changes; read "Local Setup" at the bottom before rebuilding or updating anything.

## Commands
```bash
gofmt -w . # Format (required after Go changes)
go build -o cli-proxy-api ./cmd/server # Build
go run ./cmd/server # Run dev server
go test ./... # Run all tests
go test -v -run TestName ./path/to/pkg # Run single test
go build -o test-output ./cmd/server && rm test-output # Verify compile (REQUIRED after changes)
```
- Common flags: `--config <path>`, `--tui`, `--standalone`, `--local-model`, `--no-browser`, `--oauth-callback-port <port>`

## Config
- Default config: `config.yaml` (template: `config.example.yaml`)
- `.env` is auto-loaded from the working directory
- Auth material defaults under `auths/`
- Storage backends: file-based default; optional Postgres/git/object store (`PGSTORE_*`, `GITSTORE_*`, `OBJECTSTORE_*`)

## Architecture
- `cmd/server/` — Server entrypoint
- `internal/api/` — Gin HTTP API (routes, middleware, modules)
- `internal/api/modules/amp/` — Amp integration (Amp-style routes + reverse proxy)
- `internal/thinking/` — Main thinking/reasoning pipeline. `ApplyThinking()` (apply.go) parses suffixes (`suffix.go`, suffix overrides body), normalizes config to canonical `ThinkingConfig` (`types.go`), normalizes and validates centrally (`validate.go`/`convert.go`), then applies provider-specific output via `ProviderApplier`. Do not break this "canonical representation → per-provider translation" architecture.
- `internal/runtime/executor/` — Per-provider runtime executors (incl. Codex WebSocket)
- `internal/translator/` — Provider protocol translators (and shared `common`)
- `internal/registry/` — Model registry + remote updater (`StartModelsUpdater`); `--local-model` disables remote updates
- `internal/store/` — Storage implementations and secret resolution
- `internal/managementasset/` — Config snapshots and management assets
- `internal/cache/` — Request signature caching
- `internal/watcher/` — Config hot-reload and watchers
- `internal/wsrelay/` — WebSocket relay sessions
- `internal/usage/` — Usage and token accounting
- `internal/home/` — CLIProxyAPIHome control plane integration (bootstrap, RESP communication, dispatch coordination)
- `internal/tui/` — Bubbletea terminal UI (`--tui`, `--standalone`)
- `sdk/cliproxy/` — Embeddable SDK entry (service/builder/watchers/pipeline)
- `test/` — Cross-module integration tests

## Code Conventions
- Keep changes small and simple (KISS)
- Comments in English only
- If editing code that already contains non-English comments, translate them to English (don’t add new non-English comments)
- For user-visible strings, keep the existing language used in that file/area
- New Markdown docs should be in English unless the file is explicitly language-specific (e.g. `README_CN.md`)
- As a rule, do not make standalone changes to `internal/translator/`. You may modify it only as part of broader changes elsewhere.
- If a task requires changing only `internal/translator/`, run `gh repo view --json viewerPermission -q .viewerPermission` to confirm you have `WRITE`, `MAINTAIN`, or `ADMIN`. If you do, you may proceed; otherwise, file a GitHub issue including the goal, rationale, and the intended implementation code, then stop further work.
- `internal/runtime/executor/` should contain executors and their unit tests only. Place any helper/supporting files under `internal/runtime/executor/helps/`.
- Follow `gofmt`; keep imports goimports-style; wrap errors with context where helpful
- Do not use `log.Fatal`/`log.Fatalf` (terminates the process); prefer returning errors and logging via logrus
- Shadowed variables: use method suffix (`errStart := server.Start()`)
- Wrap defer errors: `defer func() { if err := f.Close(); err != nil { log.Errorf(...) } }()`
- Use logrus structured logging; avoid leaking secrets/tokens in logs
- Avoid panics in HTTP handlers; prefer logged errors and meaningful HTTP status codes
- Timeouts are allowed only during credential acquisition; after an upstream connection is established, do not set timeouts for any subsequent network behavior. Intentional exceptions that must remain allowed are the Codex websocket liveness deadlines in `internal/runtime/executor/codex_websockets_executor.go`, the wsrelay session deadlines in `internal/wsrelay/session.go`, the management APICall timeout in `internal/api/handlers/management/api_tools.go`, and the `cmd/fetch_antigravity_models` utility timeouts
- Avoid wall-clock `time.Sleep` in TTL, expiration, ordering, or cache-eviction unit tests due to platform timer granularity (e.g. Windows default timer resolution of ~15.6ms) and CI jitter under load; prefer controllable clocks (`nowFunc` / mock clock), explicit timestamp manipulation, or deterministic synchronization primitives.
- Note: if modifying features that involve CLIProxyAPIHome, check if corresponding updates are needed in the CLIProxyAPIHome repository.
- Endpoints under the `/v0/management` base URL are deprecated and no longer maintained. For any feature changes, do not modify endpoints under `/v0/management` unless necessary to fix compilation errors.

## Local Setup (personal fork, not upstreamed)

Windows-only personal build. The binary is produced locally and is the only thing that is actually used; no PR is ever sent upstream.

### Remotes and branches
- `origin` = https://github.com/zlZayn/CLIProxyAPI (personal **public** fork, backup only)
- `upstream` = https://github.com/router-for-me/CLIProxyAPI
- `local-autobrowser` = the working branch, based on upstream tag `v8.0.7`, carrying the local commits listed below. Rebase this branch onto new upstream release tags; do not develop on `main`.
- `main` is kept identical to `upstream/main` (reset with `git branch -f main upstream/main`).
- github.com is **not** reachable directly from this machine. Route git traffic through the local proxy: `git -c http.proxy=http://127.0.0.1:7897 ...` (7897 is the local Clash/mihomo mixed port). The proxy is occasionally flaky; retry on `schannel: failed to receive handshake`.

### Local commits on `local-autobrowser`
1. `local: open the management control panel on startup`
2. `local: add helper scripts to rebuild and update from upstream`

### Local feature: open the control panel on startup
- `cmd/server/main.go`: `shouldOpenControlPanel`, `openControlPanelWhenReady`, `controlPanelHost`, `waitForServerReady`; wired in the plain-server branch of `main()` right before `cmd.StartServiceWithPluginHost`.
- Opens `http(s)://<host>:<port>/management.html` in the default browser once the port accepts a TCP connection (15s budget, best effort).
- Skipped when: `--no-browser`, `Home.Enabled`, `remote-management.disable-control-panel`, or an empty management key (Management API disabled). Skips and failures only log at debug level.
- `--no-browser` now covers both the OAuth flows and the control panel; its help text was updated accordingly.
- Unit tests: `TestShouldOpenControlPanel`, `TestControlPanelHost` in `cmd/server/main_test.go`.

### Build and update
- `powershell -ExecutionPolicy Bypass -File .\build-local.ps1` — rebuilds `cli-proxy-api.exe` (Windows/amd64, CGO on, MinGW from `.toolchain/mingw64/bin`, `GOPROXY=https://goproxy.cn,direct`). Version/commit come from the nearest git tag, and it refuses to run while the exe is running.
- `powershell -ExecutionPolicy Bypass -File .\update-upstream.ps1` — fetches `upstream` tags through the proxy, rebases the current branch onto the newest `v*` tag, then rebuilds.
- The upstream release is built with `CGO_ENABLED=1` on Windows, so dynamic-library plugins only work when the local build does the same (hence the MinGW toolchain).

### Runtime environment (never commit)
- `config.yaml` — server `host`/`port` (8317) and `remote-management.secret-key`, stored as a **bcrypt hash** (both v7 and v8 accept that form; v8 hashes plaintext on startup and writes the hash back). Also configures `plugins.configs` per plugin.
- `plugins/*.dll` — from https://github.com/mmqz/cpa-multi-plugins releases (`cpa-multi-plugins-windows-amd64.zip`); each plugin must be explicitly enabled under `plugins.configs`, otherwise the host does not even load it. Previous DLLs are kept as `plugins/<id>.dll.bak-<version>`.
- `static/management.html` — auto-downloaded control panel (Cli-Proxy-API-Management-Center), refreshed every ~3h. Panel v1.25+ requires the **v8** Management API (`/v8/management`), so an old (v7) backend makes the panel fail with "legacy backend"; this is why the build must stay on v8.
- `auths/`, `logs/`, `.toolchain/`, the exe itself, and `*.bak*` backups are git-ignored.
- `plugin-src/` holds local plugin sources (standalone Go module) and is git-ignored; back it up separately if needed.
- Gotcha: `.toolchain/` contains ~11.9k files. If its `.gitignore` entry is ever dropped, the IDE source-control panel reports thousands of untracked files.

### Keeping this file and resolving rebase conflicts
- `AGENTS.md` is tracked by upstream (the `.gitignore` entry does not apply to tracked files), so the local notes above live in a local commit together with the helper scripts. That keeps the working tree clean, which the rebase in `update-upstream.ps1` requires.
- If a rebase stops on a conflict:
  - fix the files, `git add` them, then `git rebase --continue`
  - or drop the conflicting local commit with `git rebase --skip`
  - or undo the whole rebase with `git rebase --abort`
- After a successful rebase, run `build-local.ps1` to produce a matching exe, and keep `main` aligned with `upstream/main` (`git branch -f main upstream/main`).
- Pushing from this machine needs the proxy **and** the OpenSSL TLS backend:
  `git -c http.proxy=http://127.0.0.1:7897 -c http.sslBackend=openssl push origin local-autobrowser`
  (the default schannel backend intermittently fails with `failed to receive handshake`).
