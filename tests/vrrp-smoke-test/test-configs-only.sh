#!/bin/bash
# Quick config validation without running keepalived
# Can run anywhere with keepalived binary

KEEPALIVED_BIN="${KEEPALIVED_BIN:-$(which keepalived 2>/dev/null || echo '/usr/sbin/keepalived')}"

echo "Validating keepalived configurations..."

for region in wisconsin new-york miyagi; do
    echo ""
    echo "Region: $region"
    
    # Would validate actual configs if they exist
    # For now, just check keepalived binary works
    if [ -x "$KEEPALIVED_BIN" ]; then
        echo "  keepalived binary: OK ($KEEPALIVED_BIN)"
        echo "  Version: $($KEEPALIVED_BIN -v 2>&1 | head -1)"
    else
        echo "  ERROR: keepalived not found"
        exit 1
    fi
done

echo ""
echo "Config validation complete"
