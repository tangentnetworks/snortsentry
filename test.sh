#!/bin/ksh

ALERT_FILE="/var/log/snort/alert"
TEST_DIR="/tmp/snort_test"
mkdir -p "$TEST_DIR"

# Create test alerts in proper Snort format
cat > "$TEST_DIR/test_alerts.txt" << 'EOF'
[**] [1:2000:1] SCAN_V6_TEST [**] [Priority: 1] {TCP} 2001:db8:a:b:c:d:e:f:10001 -> [::1]:80
[**] [1:2000:2] SCAN_V6_TEST [**] [Priority: 1] {UDP} 2001:db8:a::f:10002 -> [::1]:53
[**] [1:2000:3] SCAN_V6_TEST [**] [Priority: 1] {TCP} [2001:db8:a::f]:10003 -> [::1]:22
[**] [1:2000:4] SCAN_V6_TEST [**] [Priority: 1] {ICMP6} fe80::dead:beef:10004 -> fe80::1:1
[**] [1:2000:5] SCAN_V6_TEST [**] [Priority: 1] {TCP} ::ffff:192.0.2.1:10005 -> 2001:db8::1:80
[**] [1:2000:6] SCAN_V6_TEST [**] [Priority: 1] {TCP} ::ffff:c000:201:10006 -> 2001:db8::1:80
[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.99:50001 -> 192.168.1.1:81
[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.99:50002 -> 192.168.1.1:82
[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.99:50003 -> 192.168.1.1:83
EOF

echo "Starting Snort alert simulation with IPv4 and IPv6 traffic..."
echo "Target file: $ALERT_FILE"
echo "Press Ctrl+C to stop early"

# Counter for sequential timestamps
counter=1

# Function to add timestamped alert
add_alert() {
    local alert_line="$1"
    local timestamp=$(date '+%m/%d-%H:%M:%S')
    printf "%s.%.6d %s\n" "$timestamp" "$counter" "$alert_line" >> "$ALERT_FILE"
    counter=$((counter + 1))
}

# Phase 1: Initial probes (slow interval)
echo "Phase 1: Initial reconnaissance..."
for i in 1 2 3; do
    # IPv4 alerts
    add_alert "[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.$((i+50)):$((50000+i)) -> 192.168.1.1:$((80+i))"

    # IPv6 alerts
    add_alert "[**] [1:2000:1] SCAN_V6_TEST [**] [Priority: 1] {TCP} 2001:db8:a:b:c:d:e:f:$((10000+i)) -> [::1]:$((80+i))"

    sleep 3
done

# Phase 2: Escalation (medium interval)
echo "Phase 2: Escalating scan..."
for i in 1 2 3 4 5; do
    # Mixed IPv4 and IPv6
    add_alert "[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.$((i+100)):$((51000+i)) -> 192.168.1.1:$((443+i))"
    add_alert "[**] [1:2000:2] SCAN_V6_TEST [**] [Priority: 1] {UDP} 2001:db8:a::f:$((11000+i)) -> [::1]:$((53+i))"

    sleep 2
done

# Phase 3: Rapid fire (fast interval - should trigger blocking)
echo "Phase 3: Rapid fire (should trigger blocking)..."
for i in 1 2 3 4 5 6 7 8 9 10; do
    # Rapid IPv4 scans from same source
    add_alert "[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 203.0.113.99:$((60000+i)) -> 192.168.1.1:$((22+i))"

    # Rapid IPv6 scans from same source
    add_alert "[**] [1:2000:3] SCAN_V6_TEST [**] [Priority: 1] {TCP} [2001:db8:dead::beef]:$((12000+i)) -> [::1]:$((8080+i))"

    # Mixed protocol attacks
    if [ $((i % 2)) -eq 0 ]; then
        add_alert "[**] [1:2000:4] SCAN_V6_TEST [**] [Priority: 1] {ICMP6} fe80::dead:beef:$((13000+i)) -> fe80::1:1"
    fi

    sleep 0.5
done

# Phase 4: IPv4 and IPv6 mixed from multiple sources
echo "Phase 4: Multi-source mixed protocol..."
# Use individual variables instead of arrays for OpenBSD compatibility
sources_ipv4_1="198.51.100.50"
sources_ipv4_2="203.0.113.100"
sources_ipv4_3="192.0.2.25"
sources_ipv4_4="198.51.100.75"

sources_ipv6_1="2001:db8:1111::1"
sources_ipv6_2="2001:db8:2222::2"
sources_ipv6_3="2001:db8:3333::3"
sources_ipv6_4="2001:db8:4444::4"

for i in 1 2 3 4; do
    case $i in
        1) ipv4_source="$sources_ipv4_1"; ipv6_source="$sources_ipv6_1" ;;
        2) ipv4_source="$sources_ipv4_2"; ipv6_source="$sources_ipv6_2" ;;
        3) ipv4_source="$sources_ipv4_3"; ipv6_source="$sources_ipv6_3" ;;
        4) ipv4_source="$sources_ipv4_4"; ipv6_source="$sources_ipv6_4" ;;
    esac

    # IPv4 from different sources
    add_alert "[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} $ipv4_source:$((55000+i)) -> 192.168.1.1:$((3306+i))"

    # IPv6 from different sources
    add_alert "[**] [1:2000:5] SCAN_V6_TEST [**] [Priority: 1] {TCP} [$ipv6_source]:$((14000+i)) -> [2001:db8::1]:$((443+i))"

    sleep 1.5
done

# Phase 5: Final burst from persistent attackers
echo "Phase 5: Final burst from persistent attackers..."
for i in 1 2 3 4 5 6 7 8; do
    # Persistent IPv4 attacker
    add_alert "[**] [1:469:3] SCAN Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.99:$((70000+i)) -> 192.168.1.1:$((21+i))"

    # Persistent IPv6 attacker
    add_alert "[**] [1:2000:6] SCAN_V6_TEST [**] [Priority: 1] {TCP} 2001:db8:persist::1:$((15000+i)) -> [::1]:$((9000+i))"

    if [ $i -eq 4 ]; then
        echo "Halfway through final phase..."
    fi
    sleep 0.8
done

echo "Snort alert simulation complete!"
echo "Generated $((counter - 1)) test alerts in $ALERT_FILE"
echo "Check PF table entries:"
echo "pfctl -t snort_block -T show"
