#!/bin/bash
# Description: Efficiently block IPs with >50 HTTP 500 responses in Privoxy logs

LOGFILE="/var/log/privoxy/logfile"
THRESHOLD=50

# Exit if log file doesn't exist
[ -f "$LOGFILE" ] || { echo "$LOGFILE not found"; exit 1; }

# Use awk to count IPs with 500 responses incrementally
awk -v threshold="$THRESHOLD" '
/500/ {
    ip_count[$1]++
}
END {
    for (ip in ip_count) {
        if (ip_count[ip] > threshold) {
            print ip, ip_count[ip]
        }
    }
}' "$LOGFILE" | while read -r ip count; do
    # Check if IP is already blocked
    if ! iptables -C INPUT -s "$ip" -j DROP &>/dev/null; then
        iptables -A INPUT -s "$ip" -j DROP
        echo "Blocked IP: $ip (500 responses: $count)"
    else
        echo "IP already blocked: $ip"
    fi
done
