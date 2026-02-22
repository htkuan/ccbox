# ccbox

安全隔離的 Docker 環境，內建 Claude Code + 防火牆，用於全自動 AI 開發。

容器透過 iptables 防火牆限制出站連線（僅白名單域名），適合搭配 `--dangerously-skip-permissions` 使用。

## 內建工具

| 工具 | 版本 | 用途 |
|------|------|------|
| Claude Code | latest | AI 輔助開發 |
| GitHub CLI (gh) | latest | Git 操作與 GitHub 授權 |
| Node.js | 22 LTS | Claude Code 運行環境 |
| Python | 3.12 | 專案開發語言 |
| Go | 1.24.0 | 專案開發語言 |
| uv | 0.10.4 | Python 套件管理 |
| git | system | 版本控制 |
| iptables + ipset | system | 出站防火牆（白名單制） |

## 快速開始

```bash
# 1. 建置與啟動
docker compose build
docker compose up -d

# 2. 首次登入（只需做一次，認證會持久化到 ./config/）
docker exec -it ccbox claude login
docker exec -it ccbox bash -c 'BROWSER=echo gh auth login -p https -h github.com'

# 3. 使用 Claude Code
docker exec -it -w /workspace/myproject ccbox claude
```

## 使用方式

```bash
# 互動模式
docker exec -it -w /workspace/myproject ccbox claude

# 全自動模式（搭配 --dangerously-skip-permissions）
docker exec -it -w /workspace/myproject ccbox \
  claude -p --dangerously-skip-permissions "分析專案架構"

# 進入容器 shell
docker exec -it ccbox bash
```

專案放在 `./workspace/` 下，容器內外即時同步，可直接用 IDE 開啟編輯：

```
host: ./workspace/myproject/   ↔   container: /workspace/myproject/
```

## 環境變數

複製 `.env.example` 為 `.env`，按需填入：

```bash
cp .env.example .env
```

| 變數 | 用途 | 預設 |
|------|------|------|
| `ANTHROPIC_API_KEY` | API Key（替代 `claude login`） | 無 |
| `CCBOX_FIREWALL` | 啟用白名單防火牆 | 無（需搭配 cap_add） |
| `ANTHROPIC_MODEL` | 指定預設模型 | sonnet |
| `DISABLE_TELEMETRY` | 停用遙測 | 無 |

## 防火牆

預設關閉。啟用需在 `docker-compose.yml` 加入：

```yaml
services:
  ccbox:
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      - CCBOX_FIREWALL=true
```

啟用後僅允許以下出站連線，其餘一律阻擋：

| 服務 | 用途 |
|------|------|
| GitHub (API/Web/Git) | 程式碼推送、PR 操作 |
| npm registry | Node.js 套件安裝 |
| api.anthropic.com | Claude API |
| sentry.io / statsig.anthropic.com | Claude Code 遙測 |
| pypi.org | Python 套件安裝 |
| DNS (port 53) / SSH (port 22) | 基礎網路服務 |
| localhost | 本地通訊 |

添加白名單域名：編輯 `init-firewall.sh` 中的 `ALLOWED_DOMAINS` 陣列。

## 掛載說明

| Host 路徑 | 容器路徑 | 用途 |
|-----------|---------|------|
| `./workspace/` | `/workspace` | 專案工作區（雙向同步） |
| `./config/claude/` | `/home/ccbox/.claude` | Claude Code 認證與設定 |
| `./config/claude.json` | `/home/ccbox/.claude.json` | Claude Code 設定檔 |
| `./config/git/` | `/home/ccbox/.config/git` | Git 使用者設定 |
| `./config/gh/` | `/home/ccbox/.config/gh` | GitHub CLI 認證 |

所有認證透過 `./config/` bind mount 持久化，重啟容器不會遺失。

## 自訂 Image

版本號集中在 Dockerfile 頂部的 Build arguments：

```dockerfile
ARG UV_VERSION=0.10.4
ARG CLAUDE_CODE_VERSION=latest
ARG NODE_MAJOR=22
ARG PYTHON_VERSION=3.12
ARG GO_VERSION=1.24.0
```

| 自訂項目 | 做法 |
|----------|------|
| 系統套件 | Dockerfile「System packages」區塊添加 |
| npm 全域工具 | Dockerfile「Global npm tools」區塊添加 |
| Python 版本 | 修改 `PYTHON_VERSION` ARG |
| Go 版本 | 修改 `GO_VERSION` ARG |
| uv 版本 | 修改 `UV_VERSION` ARG |
| 白名單域名 | 編輯 `init-firewall.sh` 的 `ALLOWED_DOMAINS` |

## 安全提醒

- 防火牆白名單制可防止程式碼外洩至未授權服務
- `--dangerously-skip-permissions` 允許 Claude 存取容器內所有掛載內容
- **僅在信任的 repository 中使用**
- 定期檢查 Claude 的操作記錄
