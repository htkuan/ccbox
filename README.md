# ccbox

安全隔離的 Docker 環境，內建 Claude Code + 防火牆，用於全自動 AI 開發。

容器透過 iptables 防火牆限制出站連線（僅白名單域名），適合搭配 `--dangerously-skip-permissions` 使用。

## 內建工具

| 工具 | 版本 | 用途 |
|------|------|------|
| Claude Code | latest | AI 輔助開發 |
| GitHub CLI (gh) | latest | Git 操作與 GitHub 授權 |
| Node.js | 22 LTS | Claude Code 運行環境 |
| uv | latest | Python 套件管理 |
| Python | 3.12 | 專案開發語言 |
| git | system | 版本控制 |
| iptables + ipset | system | 出站防火牆（白名單制） |

## 快速開始

### 1. 建置 Image

```bash
docker compose build
```

### 2. 啟動容器

```bash
docker compose up -d
```

### 3. 執行 Claude Code

```bash
# 全自動模式（指定專案目錄）
docker exec -it -w /workspace/myproject ccbox \
  claude -p --dangerously-skip-permissions "分析專案架構"

# 互動模式
docker exec -it -w /workspace/myproject ccbox claude

# 進入容器 shell
docker exec -it ccbox bash
```

### 4. 在 IDE 查看變動

直接用 IDE 開啟 `./workspace/myproject/`，容器內的所有檔案變動會即時同步。

```
ccbox/
├── workspace/          ← IDE 開這裡
│   ├── project-a/      ← 專案 A
│   └── project-b/      ← 專案 B
├── Dockerfile
├── docker-compose.yml
└── ...
```

## 專案目錄結構

容器內的 `/workspace` 對應 host 的 `./workspace/`：

```
host: ./workspace/myproject/   ↔   container: /workspace/myproject/
```

Claude Code 會在 `/workspace/{project}` 中操作，所有變動即時反映到 host。

## 防火牆

容器啟動時可選擇初始化 iptables 防火牆，僅允許以下出站連線：

| 服務 | 用途 |
|------|------|
| GitHub (API/Web/Git) | 程式碼推送、PR 操作 |
| npm registry | Node.js 套件安裝 |
| api.anthropic.com | Claude API |
| sentry.io | Claude Code 錯誤回報 |
| statsig.anthropic.com | Feature flags |
| pypi.org | Python 套件安裝 |
| DNS (port 53) | 域名解析 |
| SSH (port 22) | Git SSH 操作 |
| localhost | 本地通訊 |

其餘所有出站連線一律阻擋。

**啟用防火牆**：在 `docker-compose.yml` 中取消註解 `cap_add` 和 `CCBOX_FIREWALL=true`。

**添加白名單域名**：編輯 `init-firewall.sh` 中的 `ALLOWED_DOMAINS` 陣列。

## 首次設定

所有認證與設定都在容器內完成，透過 named volumes 持久化，重啟容器不會遺失。

### Claude Code 授權

```bash
docker exec -it ccbox claude login
```

### Git 設定

```bash
docker exec -it ccbox git config --global user.name "Your Name"
docker exec -it ccbox git config --global user.email "you@example.com"
```

### GitHub CLI 授權

在容器內登入（設 `BROWSER=echo` 避免開瀏覽器卡住）：

```bash
docker exec -it ccbox bash
BROWSER=echo gh auth login -p https -h github.com
```

終端會顯示 URL 和 one-time code，在 host 瀏覽器開啟 URL 完成授權。

## 掛載說明

| 掛載 | 容器路徑 | 類型 | 用途 |
|------|---------|------|------|
| `./workspace` | `/workspace` | bind mount | 專案工作區（雙向同步） |
| `claude-config` | `/home/ccbox/.claude` | named volume | Claude Code 認證與設定 |
| `claude-json` | `/home/ccbox/.claude.json` | named volume | Claude Code 設定檔 |
| `git-config` | `/home/ccbox/.gitconfig` | named volume | Git 使用者設定 |
| `gh-config` | `/home/ccbox/.config/gh` | named volume | GitHub CLI 認證 |

## 常用指令

```bash
# 啟動
docker compose up -d

# 在指定專案跑 claude（全自動）
docker exec -it -w /workspace/myproject ccbox \
  claude -p --dangerously-skip-permissions "你的 prompt"

# 進入容器 shell
docker exec -it ccbox bash

# 停止
docker compose down

# 重建 image
docker compose build --no-cache
```

## 安全提醒

- 防火牆白名單制可防止程式碼外洩至未授權服務
- `--dangerously-skip-permissions` 允許 Claude 存取容器內所有掛載內容
- **僅在信任的 repository 中使用**
- 定期檢查 Claude 的操作記錄
