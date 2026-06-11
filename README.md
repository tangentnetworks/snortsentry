-----

## README.md


# snortsentry - Snort-based Intrusion Prevention System

A modern Perl-based automatic IP blocking system that monitors Snort IDS alerts and dynamically blocks offending IP addresses using OpenBSD's Packet Filter (PF).

## Overview

**snortsentry** operates as a highly resilient, stateful daemon that provides **real-time, tiered blacklisting** of malicious source IP addresses detected by **Snort**, utilizing the high-performance **OpenBSD PF (Packet Filter)** firewall tables.

It reads Snort alert logs in real-time, **robustly parses and normalizes** network addresses (handling IPv4, IPv6, zone indices, and optional IPv4-mapped IPv6 translation), and atomically adds them to PF tables for immediate blocking. It features configurable block durations, priority filtering, keyword matching, whitelisting, and automatic block escalation for repeat offenders. All state (blocked IPs, expiration, and hit counts) is persisted securely using atomic file operations and checksums for reliability across reboots or crashes.

## Features

- **Location-neutral**: All paths configurable via config file or command-line
- **Real-time monitoring**: Continuously monitors Snort alert logs
- **PF integration**: Automatically manages OpenBSD PF tables for **both IPv4 and IPv6**
- **Priority filtering**: Block only alerts meeting priority thresholds
- **Keyword matching**: Filter alerts by specific patterns (e.g., "Portscan", "Exploit")
- **Whitelist support**: Protect trusted IPs from blocking
- **Block escalation**: Repeat offenses extend block duration up to configurable maximum
- **State persistence**: Dumps current blocked IPs to file for monitoring, ensuring **atomic and reliable state save**
- **Daemon mode**: Runs as background service with proper signal handling
- **Flexible logging**: Syslog integration or stdout/stderr output

## Requirements

- OpenBSD (tested on OpenBSD 7.x)
- Perl 5.x (included in base system)
- Snort IDS configured with `alert_fast` output
- Root privileges (for PF table manipulation)
- Perl Modules: `NetAddr::IP` (any version, v3.x and later supported), `JSON`

## Installation

```ksh
# Copy script
cp snortsentry /usr/local/sbin/snortsentry
chmod +x /usr/local/sbin/snortsentry

# Copy config file and configure options
cp snortsentry.conf /etc/snort/snortsentry.conf
chmod 640 /etc/snort/snortsentry.conf

# Create necessary directories
mkdir -p /var/{logs,run,db,tmp}/snortsentry
```

## Configuration

### Configuration File

The primary configuration file is `/etc/snort/snortsentry.conf`. All settings in this file can be overridden by corresponding command-line arguments, following this hierarchy:
**Command-Line Arguments > Config File > Default Values**

| Directive               | Description                                                                                     | Default Value                     |
|-------------------------|-------------------------------------------------------------------------------------------------|-----------------------------------|
| `AlertFile`             | Full path to the Snort `alert_fast` log file.                                                   | `/var/log/snort/alert`            |
| `StateFile`             | Path for the **atomic state persistence** file.                                                 | `/var/db/snortsentry.state`       |
| `BlockDuration`         | Initial block time in seconds.                                                                  | `60`                              |
| `MaxBlockDuration`      | Maximum time a persistent offender can be blocked (in seconds).                                 | `86400` (1 day)                   |
| `Priority`              | Maximum Snort priority to block (1 is highest).                                                 | `1`                               |
| `Keyword "..."`         | Case-insensitive regex pattern required in the alert message. Can be specified multiple times. | N/A (None)                         |
| `EscalationTiers`       | Comma-separated list of durations (in seconds) for subsequent blocks.                           | `60, 300, 1800, 3600`             |
| `PfAnchor`              | Name of the PF anchor.                                                                          | `snort_block`                     |
| **`UseAnchor`**         | **`yes`** or **`no`**. Toggles between **Anchor Mode** (script manages rules) and **Table Only Mode** (recommended). | `yes`        |
| `AutoWhitelistRFC1918`  | Automatically whitelist RFC 1918 (private) and link-local addresses.                            | `yes`                             |
| `UnblockOnExit`         | Remove all IPs from the PF table when the script gracefully stops.                              | `no`                              |
| `CheckInterval`         | How often (in seconds) to check the alert log file.                                             | `1`                               |


### Snort Setup

Add `alert_fast` output to `/etc/snort/snort.conf`:

```
output alert_fast: /var/log/snort/alert
```

### PF Setup (Recommended for High-Volume/Dynamic Environments)

For robust performance and to prevent conflicts with other dynamically updated tables (like bogons or blacklists), **snortsentry** is best run in its **Table Only Mode**. This mode requires you to manually define the table and the block rules in your main `/etc/pf.conf`.

Add the following to `/etc/pf.conf`:

```
# 1. Define the table and ensure it persists across reloads
table <snort_block> persist

# 2. Block for IPv4
block drop quick from <snort_block> to any

# 3. Block for IPv6
block drop quick inet6 from <snort_block> to any
```

**Note:** If using an anchor, ensure both `inet` and `inet6` block rules are defined within that anchor.

Apply configuration:

```ksh
pfctl -f /etc/pf.conf
```

## Usage

### Command-Line Options

```
Usage: ./snortsentry.pl [OPTIONS]

  -f FILE       Config file (default: /etc/snort/snortsentry.conf)
  -a FILE       Alert file (default: /var/log/snort/alert)
  -p FILE       PID file (default: /var/run/snortsentry.pid)
  -l FILE       Lock file (default: /var/run/snortsentry.lock)
  -s FILE       State file (default: /var/db/snortsentry.state)
  --log FILE    Log file (optional)
  -t NAME       PF table (default: snort_block)
  -v            Verbose (debug logging)
  -D            No daemon
  -n            Dry run
  --version     Show version
  --status      Show current status
  -h            Help

```

### Starting snortsentry

**Manual start (foreground for testing):**

```ksh
/usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf -D -v
```

**Daemon mode:**

```ksh
/usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf
```

**From rc.local:**

```ksh
# Add to /etc/rc.local
if [ -x /usr/local/sbin/snortsentry ]; then
  /usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf
fi
```
**From rcctl**
Create /etc/rc.d/snortsentry

```
#!/bin/ksh

daemon="/usr/local/sbin/snortsentry"
daemon_user="root"
daemon_flags="-f /etc/snort/snortsentry.conf"

. /etc/rc.d/rc.subr

# Set pexp to match the interpreter and the script name.
# The rc.subr script will intelligently match this pattern.
pexp="/usr/bin/perl -T ${daemon} ${daemon_flags}"

rc_cmd $1
```
Make it executable, enable, start, check status, and stop by executing:
```
# Make script execuable
chmod +x /etc/rc.d/snortsentry

# Enable snortsentry
rcctl enable snortsentry

# Start snortsentry
rcctl start snortsentry

# Status check snortsentry
rcctl check snortsentry

# Stop snortsentry
rcctl stop snortsentry
```

### Signal Handling

When Perl-based daemons are started through OpenBSD's rc subsystem, they often cannot be reliably found or killed using pgrep or pkill commands, even when specifying the script name. Unlike compiled binaries that become the process themselves, Perl scripts run under the Perl interpreter. The kernel registers perl as the process name, not snortsentry. The script path is merely an argument.

You can find the pid of snortsentry post start by running:
```
pgrep -f snortsentry
```

You can terminate the running process by executing
```
pkill -f snortsentry
```

### Test Block Escalation (Including IPv6 Testing)

To test block escalation and ensure **IPv4/IPv6 handling** is correct, you must add alerts from both families.

## 🧪 Testing and Verification

To test block escalation and ensure **IPv4 and IPv6 handling** are correct, you will use a dedicated simulation script. This script rapidly generates a mixture of unique and repeated alerts to trigger all stages of block escalation.

### 1\. The Test Script (`test.sh`)

Save the following shell script contents into a file named **`test.sh`** and ensure it has executable permissions.

```
chmod +x test.sh
```

** IMPORTANT:** Verify that the `ALERT_FILE` path in this script matches the `AlertFile` directive in your `/etc/snort/snortsentry.conf`.

```
# Start snortsentry in debug mode

/usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf -D -v
```

From another console execute test.sh
```
./test.sh
```

Monitor the `snortsentry` output in the first console. You should see logs showing **`queued block`** for new IPs, **`extended`** for repeat offenders, and **`whitelisted`** for the `fe80::` address.

**Verify Results:**
After the script finishes, run the following command to check the list of blocked IPs in the PF table:

```ksh
pfctl -t snort_block -T show
```

The output should show a list of unique IPv4 and IPv6 addresses blocked during the test, including the persistent attackers: `203.0.113.99`, `2001:db8:dead::beef`, `198.51.100.99`, and `2001:db8:persist::1`. The link-local address `fe80::dead:beef` should **not** be present due to the auto-whitelisting.

**Expected behavior:**

- Separate entries for `198.51.100.99` and `2001:db8:ffff::dead:beef` will be added to the PF table.
- Both IPs will show duration extension up to MaxBlockDuration.

**Watch in real-time:**

```ksh
# Terminal 1: Watch alerts
tail -f /var/log/snort/alert

# Terminal 2: Watch snortsentry (confirming IPv6 addresses are added cleanly)
/usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf -D -v

# Terminal 3: Watch PF table (confirming both IPv4 and IPv6 addresses are present)
watch 'pfctl -t snort_block -T show -v'
```

### Test with Real Traffic

Generate actual Snort alerts:

```
# IPv4 Port scan from another machine
nmap -sS -p 1-1000 <your_openbsd_ip>

# for port in {20..100}; do
  nc -zv -w1 <your_openbsd_ip> $port 2>&1 | grep succeeded
  sleep 0.5
done

# IPv6 Scan (ensure Snort is configured to inspect IPv6 traffic)
nmap -6 -sS -p 1-100 <your_openbsd_ipv6_address>
```

## Monitoring

### Check Running Status

```ksh
# Check if running
pgrep -f snortsentry

# View daemon logs (if running as daemon)
grep snortsentry /var/log/messages | tail -20

# View custom log (if configured in syslog and newsyslog). Please see doc file
tail -f /var/log/snortsentry.log
```

### View Blocked IPs

```ksh
# Current blocked IPs (shows both IPv4 and IPv6)
pfctl -t snort_block -T show

# Detailed state
cat /var/db/snortsentry/snortsentry

# Count of blocked IPs
pfctl -t snort_block -T show | wc -l
```

### Manual IP Management

```ksh
# Manually add IPv4
pfctl -t snort_block -T add 1.2.3.4

# Manually add IPv6
pfctl -t snort_block -T add 2001:db8::1

# Manually remove IPv4
pfctl -t snort_block -T delete 1.2.3.4

# Manually remove IPv6
pfctl -t snort_block -T delete 2001:db8::1

# Flush all blocked IPs
pfctl -t snort_block -T flush
```

## How It Works

1.  **Alert Monitoring**: snortsentry continuously reads the Snort alert\_fast log file
2.  **Alert Parsing**: Extracts priority, message/keyword, and source IP from each alert. Uses NetAddr::IP for IPv4/IPv6 normalisation. IPv4-mapped IPv6 addresses (::ffff:x.x.x.x) are transparently rewritten to native IPv4 using pure regex — compatible with NetAddr::IP v3.x and later without requiring v4.x methods..
3.  **Filtering**: Checks against priority threshold, keyword patterns, and whitelist
4.  **Blocking**: Adds matching IPs to PF table using `pfctl -t <table> -T add <ip>`. The process includes robust **retry and requeueing logic** for transient PF errors.
5.  **Escalation**: Repeat offenses from same IP extend block duration (capped at MaxBlockDuration)
6.  **Expiration**: After block duration expires, IP is automatically removed from PF table
7.  **State Dump**: Periodically writes current blocked IPs to dump file for monitoring using **atomic writes and checksum validation** to prevent data corruption.

## Alert Format

snortsentry parses Snort's `alert_fast` format:

```
MM/DD-HH:MM:SS.UUUUUU  [**] [GID:SID:REV] Message [**] [Classification: class] [Priority: N] {PROTO} SRC_IP:PORT -> DST_IP:PORT
```

**Example (IPv4):**

```
11/26-10:45:24.234567  [**] [1:1421:11] SNORT STREAM TCP Portscan [**] [Classification: Attempted Information Leak] [Priority: 1] {TCP} 198.51.100.99:54321 -> 192.168.1.1:80
```

**Example (IPv6):**

```
11/26-10:45:24.234567  [**] [1:1421:11] SNORT STREAM UDP DNS Query [**] [Classification: Attempted Denial of Service] [Priority: 1] {UDP} [2001:db8:a::1%if0]:5353 -> [ff02::fb]:5353
```

## Troubleshooting

### snortsentry Exits Immediately

  - Check config file exists and is readable
  - Verify AlertFile path is correct and file exists
  - Check PidFile directory exists and is writable
  - Run with `-D -v` to see error messages

### No IPs Being Blocked

  - Verify Snort is generating alerts: `tail -f /var/log/snort/alert`
  - Check priority threshold in config (Priority 1 = highest)
  - Verify keywords match alert messages
  - Check if IPs are whitelisted
  - Run snortsentry with `-v` flag for verbose output

### PF Table Errors

  - Verify table exists: `pfctl -t snort_block -T show`
  - Check PF rules for **both `inet` (IPv4) and `inet6` (IPv6) block rules**: `pfctl -sr | grep snort_block`
  - Ensure table is defined in `/etc/pf.conf` as `table <snort_block> persist`
  - Reload PF: `pfctl -f /etc/pf.conf`

### Permission Issues

  - snortsentry must run as root (needs pfctl access)
  - Ensure alert file is readable: `ls -l /var/log/snort/alert`
  - Check PID file directory permissions



## Architecture

```
┌─────────────────────────────┐
│           Snort             │
│  Intrusion Detection System │
│  - Generates alerts for     │
│    IPv4 and IPv6 traffic    │
└─────────────┬───────────────┘
              │ Writes to alert_fast-formatted log
              ▼
┌─────────────────────────────┐
│           Alert             │
│   (alert_fast log format)   │
│  - Records detailed alerts  │
│    from Snort               │
└─────────────┬───────────────┘
              │ Monitored and parsed by
              ▼
┌─────────────────────────────┐
│         SnortSentry         │
│  Alert Management Daemon    │
│  - Parses alerts, normalizes│
│    IP addresses (IPv4/IPv6) │
│  - Filters alerts by        │
│    priority, keywords, and  │
│    whitelist criteria       │
│  - Manages duration of IP   │
│    block entries            │
│  - Executes pfctl commands  │
│    to update firewall rules │
└─────────────┬───────────────┘
              │ Updates block list
              ▼
┌─────────────────────────────┐
│     PF Table: snort_block   │
│  - Contains blocked IPs     │
│    (IPv4 and IPv6)          │
│  - Entries expire           │
│    automatically            │
└─────────────┬───────────────┘
              │ Enforced by
              ▼
┌─────────────────────────────┐
│   OpenBSD Packet Filter     │
│  (pf) firewall controlling  │
│  - Blocks network traffic   │
│    based on snort_block IPs │
│  - Applies to net/internet6 │
└─────────────────────────────┘

```

## Files

  - `/usr/local/sbin/snortsentry` - Main executable
  - `/etc/snort/snortsentry.conf` - Configuration file
  - `/var/log/snort/alert` - Snort alerts (configurable)
  - `/var/run/snortsentry/snortsentry.pid` - PID file (configurable)
  - `/var/db/snortsentry/snortsentry` - State dump (configurable)


## Performance

  - Minimal CPU usage (sleeps between checks)
  - Memory footprint: \~5-10MB
  - Handles thousands of blocked IPs efficiently
  - Configurable check interval (default: 1 second)


## Security Considerations

  - **Whitelist critical IPs**: Always whitelist your management IPs to avoid lockout
  - **Test in non-daemon mode first**: Verify configuration before production deployment
  - **Monitor false positives**: Review blocked IPs regularly
  - **Adjust thresholds**: Tune Priority and MaxBlockDuration for your environment
  - **Backup access**: Ensure console/KVM access in case of lockout


## Tangent Networks Live Demo Use

This implementation was specifically designed for Tangent Networks Securty Lab demonstrations:

  - **Self-contained**: All paths configurable, no hardcoded dependencies
  - **Observable**: **Atomic state saves** and verbose mode for educational visibility
  - **Testable**: Easy to generate fake alerts for demonstration and **IPv6 testing**
  - **Documented**: Comprehensive README for experimenting
  - **Flexible**: Priority/keyword filtering demonstrates security policy concepts



## License

BSD 3-Clause license

## Author

David Peter, Tangent Networks

## Contributing

Contributions welcome\! Please test thoroughly on OpenBSD before submitting.

## See Also

  - snort(8) - Network Intrusion Detection System
  - pf(4) - Packet Filter
  - pf.conf(5) - Packet Filter configuration
  - pfctl(8) - Control the packet filter
