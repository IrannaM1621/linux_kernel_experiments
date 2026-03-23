# ftrace_driver_debug.sh

> **Trace every function call inside a loaded Linux kernel driver — no recompile, no JTAG, no kernel rebuild required.**

A production-safe bash script that automates the full `ftrace` workflow for kernel driver debugging.
Built and battle-tested while upstreaming a Linux crypto driver and debugging firmware on a custom RISC-V + FPGA accelerator platform.

---

## The problem this solves

The manual `ftrace` workflow has a footgun that nobody talks about:

```bash
# If you forget this line...
echo your_func > /sys/kernel/debug/tracing/set_ftrace_filter

# ...and then enable tracing:
echo 1 > /sys/kernel/debug/tracing/tracing_on
```

You are now tracing **every single kernel function** — millions of events per second.
Your log is unreadable. Your system degrades. You forget to turn it off.

This script **always** filters to your driver's functions only, handles all setup and teardown, and leaves the system clean no matter how it exits.

---

## Features

| Feature | Detail |
|---|---|
| **Auto symbol resolution** | Reads all `t/T` function symbols from `/proc/kallsyms` automatically |
| **Precise filter** | Only your driver's functions go into `set_ftrace_filter` |
| **Manual stop mode** | Tracing runs indefinitely — press **Enter** when done |
| **Timed mode** | Auto-stops after N seconds for scripted/CI runs |
| **Live event counter** | Shows events in the buffer every 5 seconds while running |
| **Safe cleanup** | `trap cleanup EXIT` — tracing always disabled on exit, error, or Ctrl+C |
| **Flexible input** | Accepts module name, `.ko` filename, or full `/path/to/driver.ko` |
| **Rich diagnostics** | On every failure: ftrace state, kernel config, kallsyms breakdown, modinfo, nm |
| **Timestamped log** | Saves trace output + dmesg (new lines only) + buffer stats |
| **Two tracers** | `function_graph` (call graph + timing) or `function` (flat list + timestamp) |

---

## Requirements

| Requirement | Detail |
|---|---|
| **Kernel config** | `CONFIG_FTRACE=y`, `CONFIG_KALLSYMS=y`, `CONFIG_DEBUG_FS=y` |
| **Privileges** | `root` / `sudo` |
| **Shell** | `bash` 4+ |
| **Driver state** | Module must already be loaded before running this script |
| **Dependencies** | None — pure bash |

Check your kernel has the required config:

```bash
zcat /proc/config.gz | grep -E "FTRACE|KALLSYMS|DEBUG_FS"
# or
grep -E "FTRACE|KALLSYMS|DEBUG_FS" /boot/config-$(uname -r)
```

---

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/ftrace-driver-debug.git
cd ftrace-driver-debug
chmod +x ftrace_driver_debug.sh
```

---

## Usage

```bash
sudo ./ftrace_driver_debug.sh <driver> [duration_seconds] [tracer]
```

### Arguments

| Argument | Default | Description |
|---|---|---|
| `driver` | *(required)* | Module name, `.ko` filename, or full `.ko` path |
| `duration_seconds` | `0` | `0` = manual stop (press Enter); `N` = auto-stop after N seconds |
| `tracer` | `function_graph` | `function_graph` or `function` |

### All input forms are equivalent

```bash
sudo ./ftrace_driver_debug.sh my_driver
sudo ./ftrace_driver_debug.sh my_driver.ko
sudo ./ftrace_driver_debug.sh /home/user/build/my_driver.ko
```

---

## Examples

```bash
# Manual stop — tracing runs until you press Enter (recommended)
sudo ./ftrace_driver_debug.sh my_driver

# Manual stop — explicit zero
sudo ./ftrace_driver_debug.sh my_driver 0

# Timed — auto-stop after 30 seconds
sudo ./ftrace_driver_debug.sh my_driver 30

# Timed — flat function list instead of call graph
sudo ./ftrace_driver_debug.sh my_driver 30 function

# Full .ko path, manual stop, call graph
sudo ./ftrace_driver_debug.sh /home/user/drivers/my_driver.ko 0 function_graph
```

---

## How it works — 10 steps

```
STEP 0   Validate args, check root, normalise driver name
STEP 1   Verify debugfs mounted at /sys/kernel/debug (auto-mount if needed)
STEP 2   Confirm module is loaded via lsmod — never loads or unloads it
STEP 3   Check requested tracer is available on this kernel
STEP 4   Resolve all t/T function symbols from /proc/kallsyms
STEP 5   Clear trace ring buffer and per-CPU buffers
STEP 6   Set tracer (goes through nop first for a clean state)
STEP 7   Write driver symbols to set_ftrace_filter — driver functions only
STEP 8   Enable tracing — wait for Enter or countdown timer
STEP 9   Disable tracing — show per-CPU buffer stats
STEP 10  Save log file: trace output + dmesg + metadata
CLEANUP  Always runs on exit — disables tracing, clears filter, resets to nop
```

---

## Collection modes

### Manual mode — default (`duration=0`)

Tracing runs indefinitely. A live ticker updates every second with elapsed time,
and shows the event count every 5 seconds. Press **Enter** when you have captured enough.

```
  [ OK ]  Tracing is ACTIVE

  Manual mode — tracing is running indefinitely.
  Exercise your driver in another terminal:
    cat /dev/my_driver
    echo test > /dev/my_driver

  Press ENTER at any time to stop tracing and save the log.

  Elapsed: 00:05   tracing_on=1
  Elapsed: 00:10   Events in buffer: 0
  Elapsed: 00:15   Events in buffer: 47       <- driver was triggered
  Elapsed: 00:20   Events in buffer: 103
                                              <- press Enter here
  Tracing stopped by user after 22s.
```

### Timed mode (`duration=N`)

Tracing stops automatically after N seconds with a live countdown.
Ideal for scripted runs, CI pipelines, or repeatable test sequences.

```
  Collecting trace for 30 seconds...

  Time remaining:  30s   tracing_on=1
  Time remaining:  25s   Events captured: 0
  Time remaining:  20s   tracing_on=1
  Time remaining:  15s   Events captured: 83
  ...
  Collection window complete (30s).
```

---

## What gets captured — and what does not

### Captured

- Every driver function called **after** the script starts tracing
- Background kernel threads and interrupt handlers inside your driver
- Any operation triggered from userspace (open / read / write / ioctl / close)
- New `dmesg` lines that appear during the capture window

### Not captured

- Anything that happened **before** the script started — ftrace only records while `tracing_on=1`
- There is no "record from boot" mode; the ring buffer is empty until tracing is enabled

> **For pre-run messages:** If your driver uses `pr_info()`, `dev_err()`, or `dev_dbg()`,
> those messages remain in the kernel ring buffer. Run `dmesg` to see them.
> The script also saves all new dmesg lines from the capture window to the log automatically.

---

## Output log

Every run creates a timestamped log file:

```
./ftrace_logs/my_driver_20250316_143022.log
```

Contents:

```
============================================================
 FTRACE DRIVER DEBUG LOG
============================================================
 Driver       : my_driver
 Tracer       : function_graph
 Duration     : 22s
 Captured at  : Mon Mar 16 14:30:22 UTC 2025
 Kernel       : 6.8.0-45-generic
 Host         : kernelninja
============================================================

 SYMBOLS TRACED  (6 total)
============================================================
my_driver_open
my_driver_read
my_driver_write
my_driver_release
my_driver_ioctl
my_driver_probe

============================================================
 TRACE OUTPUT
============================================================
# tracer: function_graph
#
# CPU  DURATION         FUNCTION CALLS
 0)               |  my_driver_open() {
 0)   2.341 us    |    my_driver_read();
 0) + 15.432 us   |  }

============================================================
 DMESG  (new lines during trace window)
============================================================
[12345.678] my_driver: device opened by pid 4821
[12347.123] my_driver: read 256 bytes
```

### Reading the log

```bash
# Full log
less ftrace_logs/my_driver_20250316_143022.log

# Jump to trace output
grep -A 1000 'TRACE OUTPUT' ftrace_logs/my_driver_*.log | less

# Find a specific function
grep 'my_driver_write' ftrace_logs/my_driver_*.log

# Show timing lines only (function_graph tracer)
grep 'us\|ms' ftrace_logs/my_driver_*.log | head -50

# Show dmesg section
grep -A 100 'DMESG' ftrace_logs/my_driver_*.log
```

---

## Troubleshooting

### Trace is empty

```
[WARN]  Buffer empty — no calls captured.
```

**Cause 1 — Driver not exercised during the window**

Open a second terminal and trigger the driver while the script is collecting:

```bash
cat /dev/my_driver
echo test > /dev/my_driver
dd if=/dev/my_driver bs=1 count=16
```

**Cause 2 — Functions inlined by the compiler**

The compiler merged small functions into their callers. ftrace cannot hook inlined code.
Fix — add to your driver `Makefile` and rebuild:

```makefile
ccflags-y += -O0 -fno-inline
```

Then `rmmod` and `insmod` the driver before re-running the script.

**Cause 3 — Try the flat tracer**

```bash
sudo ./ftrace_driver_debug.sh my_driver 10 function
```

---

### Module not found

```
[FAIL]  Module 'my_driver' is NOT loaded.
```

The script prints the full `lsmod` and matching `dmesg` lines to help you find the right name.

```bash
sudo insmod /path/to/my_driver.ko
# or
sudo modprobe my_driver
```

The script **never** loads or unloads modules itself.

---

### No traceable symbols

```
[FAIL]  No traceable function symbols found for 'my_driver'.
```

The script dumps the full kallsyms symbol-type breakdown for your module.

- **Zero entries in kallsyms** — module name mismatch. The script lists all module names currently present.
- **Entries exist but no t/T type** — all functions are inlined. Rebuild with `-O0 -fno-inline`.

---

### debugfs not mounted

The script auto-mounts it. If that fails it prints the full mount table and kernel config.

---

### Tracer not available

```
[FAIL]  Tracer 'function_graph' not available on this kernel.
```

The script prints all available tracers. Try `function`, or enable `CONFIG_FUNCTION_GRAPH_TRACER=y`.

---

## ftrace path reference

```
/sys/kernel/debug/tracing/
├── tracing_on              0 = off   1 = on
├── current_tracer          active tracer name
├── available_tracers       what this kernel supports
├── set_ftrace_filter       which functions to trace  (empty = ALL = dangerous)
├── trace                   ring buffer output — read this for results
├── buffer_size_kb          ring buffer size per CPU (KB)
└── per_cpu/
    ├── cpu0/
    │   ├── trace           per-CPU ring buffer content
    │   └── stats           entries, overruns, dropped event counts
    └── cpu1/ ...
```

---

## Author

**Iranna Mundaganur** — Embedded Systems & Linux Kernel Engineer

[LinkedIn](https://www.linkedin.com/in/iranna-mundaganur-8b83b1192/)

---
