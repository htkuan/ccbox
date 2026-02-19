#!/bin/bash
# ====================================================================
# ccbox 防火牆初始化腳本
# ====================================================================
# 基於 Anthropic 官方 devcontainer 防火牆腳本改寫。
# 實現白名單制出站連線，僅允許存取以下服務：
#   - GitHub（API / Web / Git）
#   - npm registry
#   - Anthropic API（Claude）
#   - Sentry / Statsig（Claude Code 遙測）
#   - PyPI（Python 套件）
#
# 需要 --cap-add=NET_ADMIN --cap-add=NET_RAW 才能運作。
#
# 擴充：在 ALLOWED_DOMAINS 陣列中添加需要的域名即可。
# ====================================================================

set -euo pipefail
IFS=$'\n\t'

# ── 可自訂的白名單域名 ─────────────────────────────────────────────
# 擴充：在此陣列添加需要白名單的域名
ALLOWED_DOMAINS=(
    # npm registry
    "registry.npmjs.org"
    # Anthropic API（Claude Code 核心）
    "api.anthropic.com"
    # Claude Code 遙測與 feature flags
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    # PyPI（Python 套件下載）
    "pypi.org"
    "files.pythonhosted.org"
)

# ── 1. 保存 Docker DNS 規則（必須在 flush 前執行）────────────────
echo "[firewall] Saving Docker DNS rules..."
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127.0.0.11" || true)

# ── 2. 清除現有規則 ────────────────────────────────────────────────
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# ── 3. 還原 Docker DNS 規則 ────────────────────────────────────────
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "[firewall] Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "[firewall] No Docker DNS rules to restore"
fi

# ── 4. 基礎規則（DNS / SSH / localhost）───────────────────────────
# 允許 DNS 出站
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# 允許 SSH 出站
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# 允許 localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ── 5. 建立 IP 白名單集合 ──────────────────────────────────────────
ipset create allowed-domains hash:net

# ── 6. GitHub IP 範圍（動態取得）───────────────────────────────────
echo "[firewall] Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --connect-timeout 10 https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "[firewall] ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "[firewall] ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "[firewall] Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "[firewall] ERROR: Invalid CIDR from GitHub: $cidr"
        exit 1
    fi
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# ── 7. 解析並添加白名單域名 ────────────────────────────────────────
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "[firewall] Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "[firewall] WARNING: Failed to resolve $domain, skipping"
        continue
    fi
    while read -r ip; do
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            ipset add allowed-domains "$ip" 2>/dev/null || true
        fi
    done <<< "$ips"
done

# ── 8. 允許 host 網路通訊 ──────────────────────────────────────────
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "[firewall] Host network: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
else
    echo "[firewall] WARNING: Could not detect host network"
fi

# ── 9. 設定預設策略為 DROP ─────────────────────────────────────────
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 允許已建立的連線
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 僅允許白名單 IP 出站
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# 其餘一律拒絕（立即回應，不 hang）
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# ── 10. 驗證防火牆 ─────────────────────────────────────────────────
echo "[firewall] Verifying..."

# 應該被阻擋的
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "[firewall] ERROR: example.com reachable — firewall NOT working!"
    exit 1
fi
echo "[firewall] PASS: example.com blocked"

# 應該放行的
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "[firewall] ERROR: api.github.com unreachable — whitelist broken!"
    exit 1
fi
echo "[firewall] PASS: api.github.com reachable"

echo "[firewall] Firewall active (whitelist-only outbound)"
