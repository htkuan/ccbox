#!/bin/bash
# ====================================================================
# ccbox entrypoint
# ====================================================================
# 1. 若 CCBOX_FIREWALL=true，初始化防火牆
# 2. 執行傳入的 CMD
#
# 防火牆預設關閉。啟用方式：
#   docker run -e CCBOX_FIREWALL=true --cap-add=NET_ADMIN --cap-add=NET_RAW ...
# ====================================================================

set -e

# ── 防火牆初始化（僅在明確啟用時執行）─────────────────────────────
if [ "${CCBOX_FIREWALL:-false}" = "true" ]; then
    if sudo /usr/local/bin/init-firewall.sh; then
        echo ""
        echo "=========================================="
        echo "  ccbox: firewall ACTIVE"
        echo "=========================================="
    else
        echo ""
        echo "=========================================="
        echo "  ccbox: firewall FAILED"
        echo "  Ensure --cap-add=NET_ADMIN --cap-add=NET_RAW"
        echo "=========================================="
    fi
    echo ""
fi

# ── 執行 CMD ──────────────────────────────────────────────────────
exec "$@"
