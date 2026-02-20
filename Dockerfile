# ====================================================================
# ccbox — Sandboxed Claude Code Runner
# ====================================================================
# 安全隔離的 Docker 環境，用於全自動運行 Claude Code。
# 內建 iptables 防火牆（僅白名單出站），適合搭配
# --dangerously-skip-permissions 使用。
#
# 內建工具：Node.js, Python, GitHub CLI, Claude Code, uv
# 安全機制：iptables + ipset 防火牆（白名單制）
#
# 擴充方式：
#   - 加入新的系統套件 → 在「System packages」區塊的對應分類添加
#   - 加入新的 npm 全域工具 → 在「Global npm tools」區塊添加
#   - 加入新的 Python 版本 → 修改 PYTHON_VERSION ARG
#   - 加入新的白名單域名 → 編輯 init-firewall.sh
# ====================================================================

FROM debian:bookworm

# ── Build arguments（集中管理版本號，方便升級）─────────────────────
ARG CLAUDE_CODE_VERSION=latest
ARG NODE_MAJOR=22
ARG PYTHON_VERSION=3.12
ARG GO_VERSION=1.24.0

# ── 1. System packages ─────────────────────────────────────────────
# 單一 RUN 減少 image layer 數量；apt cache 最後統一清除
RUN apt-get update \
    #
    # --- 基礎工具 ---
    && apt-get install -y --no-install-recommends \
       git curl wget ca-certificates build-essential gpg sudo \
       jq less procps unzip man-db locales \
    #
    # --- UTF-8 locale（支援中文輸入與正確的終端寬字元計算）---
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    #
    # --- 防火牆（iptables + ipset，用於域名白名單機制）---
    # 需搭配 --cap-add=NET_ADMIN --cap-add=NET_RAW 使用
    && apt-get install -y --no-install-recommends \
       iptables ipset iproute2 dnsutils aggregate \
    #
    # --- GitHub CLI ---
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    #
    # --- Node.js LTS（Claude Code 需要 Node >= 18）---
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    #
    # --- 清除 apt cache 縮減 image 大小 ---
    && rm -rf /var/lib/apt/lists/*

# ── 2. Global npm tools ────────────────────────────────────────────
# Claude Code CLI（全域安裝）
# 擴充：在此處添加其他全域 npm 工具，例如：
#   && npm install -g typescript \
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# ── 3. uv（Python 套件管理 + 自帶 Python 版本管理）─────────────────
# 從官方 image 直接 COPY 二進位，零額外依賴
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ── 3b. Go ───────────────────────────────────────────────────────────
# 從官方 tarball 安裝，版本透過 ARG 控制
ARG TARGETARCH
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz \
    | tar -C /usr/local -xz

# ── 4. Firewall script ─────────────────────────────────────────────
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

# ── 5. Git credential helper（系統層級，不被 ~/.gitconfig 掛載覆蓋）─
RUN git config --system credential.helper '!gh auth git-credential'

# ── 6. 非 root 使用者 ──────────────────────────────────────────────
# ccbox 使用者僅有 init-firewall.sh 的 NOPASSWD sudo 權限
RUN useradd -m -s /bin/bash ccbox \
    && echo "ccbox ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
       > /etc/sudoers.d/ccbox-firewall \
    && chmod 0440 /etc/sudoers.d/ccbox-firewall

# ── 7. 使用者空間設定（以 ccbox 身份）──────────────────────────────
USER ccbox
RUN mkdir -p /home/ccbox/.config

# ── 8. Python（透過 uv 安裝到 ~/.local/）───────────────────────────
# 擴充：可安裝多個版本，例如 uv python install 3.11 3.12
RUN uv python install ${PYTHON_VERSION}

# ── 9. 工作目錄與環境變數 ─────────────────────────────────────────
WORKDIR /workspace

ENV SHELL=/bin/bash
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV PATH="/usr/local/go/bin:/home/ccbox/go/bin:/home/ccbox/.local/bin:/workspace/.venv/bin:$PATH"

# ── Entrypoint & 預設命令 ──────────────────────────────────────────
# CCBOX_FIREWALL=true 時自動執行防火牆腳本，之後 exec CMD
# 預設 CMD 為 sleep infinity（搭配 docker compose 使用）
# 可被 docker run 覆蓋為 claude -p ... 等指令
ENTRYPOINT ["/bin/bash", "-c", "[ \"${CCBOX_FIREWALL:-}\" = true ] && sudo /usr/local/bin/init-firewall.sh; exec \"$@\"", "--"]
CMD ["sleep", "infinity"]
