# Status Hub — Feature Brainstorm 🧠

## What You Already Have
| Area | Status |
|------|--------|
| CPU, Memory, Storage, Network | ✅ Live via collector |
| Battery, Temperature | ✅ Live via collector |
| Docker Containers | ✅ Live via collector |
| Alerts & Notifications (ntfy) | ✅ Working |
| Drag-and-Drop + Pin to Menu Bar | ✅ Just shipped |
| Theme / Accent Colors | ✅ 9 options |

---

## 🔥 High-Value Ideas (Recommended Next)

### 1. **Uptime & Last-Seen Tracker**
Show how long your Ubuntu machine has been online, and when it was last seen.
- Add `uptime` to the collector (already available via `gopsutil`)
- Show "Online 3d 14h" or "Last seen 5 min ago" in the dropdown
- **Effort**: Low · **Value**: High — first glance tells you if it's alive

### 2. **Quick SSH Button**
One-click to open Terminal.app with an SSH session to your Ubuntu box.
- Button in the dropdown: "SSH into homeserver"
- Opens `ssh elite@100.108.187.59` in a new Terminal window
- **Effort**: Low · **Value**: High — saves you opening terminal and typing every time

### 3. **Process / Top Services Widget**
Show the top 5 processes by CPU or memory usage.
- Collector reads `/proc` or uses `gopsutil.Process()`
- New widget kind: `top-processes` showing process name + CPU%
- **Effort**: Medium · **Value**: High — catches runaway processes from your Mac

### 4. **System Logs Widget (Live Tail)**
Stream the last N lines of `journalctl` or `syslog` from the Ubuntu machine.
- New WebSocket channel for log streaming
- Show last 10 log lines in a scrollable widget
- Filter by service (e.g., only Docker, only SSH)
- **Effort**: Medium · **Value**: High — see errors without SSH-ing in

### 5. **Remote Command Execution**
Run predefined safe commands from the Mac menu bar.
- Example: "Restart Docker", "Clear /tmp", "Check disk health"
- Admin-only, requires confirmation dialog
- **Effort**: Medium · **Value**: Very High — real productivity gain

---

## 📊 Monitoring Enhancements

### 6. **Historical Charts (Sparklines)**
Tiny inline charts showing CPU/memory/temperature trends over the last hour.
- Store last 60 snapshots in memory on the hub
- Render as a SwiftUI `Path` sparkline in each widget card
- **Effort**: Medium · **Value**: High — trends matter more than point-in-time values

### 7. **Disk Health (S.M.A.R.T.)**
Read S.M.A.R.T. data to warn about failing drives.
- Collector calls `smartctl` if available
- New alert rule: "Disk health degraded"
- **Effort**: Low · **Value**: Medium — saves you from sudden data loss

### 8. **GPU Monitoring** (if applicable)
If your Ubuntu box has an NVIDIA GPU, show GPU temp + utilization.
- Collector reads `nvidia-smi` output
- **Effort**: Low · **Value**: Medium (only if you have a GPU)

### 9. **Swap Usage Widget**
Show swap in/out separately from RAM.
- Already partially collected; just need a new widget kind
- **Effort**: Very Low · **Value**: Low-Medium

---

## 🚀 Productivity Features

### 10. **Clipboard Sync**
Sync clipboard between Mac and Ubuntu via the hub.
- Mac copies text → pushes to hub → Ubuntu pulls it (and vice versa)
- **Effort**: High · **Value**: Very High — game changer for dual-machine workflow

### 11. **File Drop** 
Drag a file onto the menu bar icon to transfer it to Ubuntu.
- Uses the hub as a relay; file stored temporarily
- Ubuntu collector picks it up and saves to `~/incoming/`
- **Effort**: High · **Value**: High — quick file transfer without scp

### 12. **Wake-on-LAN**
If your Ubuntu machine is sleeping or powered off, send a WoL magic packet.
- Button in dropdown: "Wake homeserver"
- Sends WoL packet over Tailscale
- **Effort**: Low · **Value**: Medium — useful if you put it to sleep

### 13. **Scheduled Reports**
Daily email/notification summary: "Yesterday: avg CPU 23%, peak 81%, 2 alerts fired"
- Hub generates a summary at midnight
- Sends via ntfy
- **Effort**: Medium · **Value**: Medium

---

## 🎨 UX Polish

### 14. **Menu Bar Icon Animations**
Pulse or change the icon color based on system health.
- Red pulse for critical alerts
- Subtle breathing animation when connected and healthy
- **Effort**: Low · **Value**: Medium — instant visual feedback

### 15. **Keyboard Shortcuts**
`⌘+Shift+S` to toggle the dropdown, `⌘+,` to open Settings.
- Uses `.keyboardShortcut()` in SwiftUI
- **Effort**: Very Low · **Value**: Medium

### 16. **Launch at Login**
Auto-start the app when macOS boots.
- Add `SMAppService.mainApp.register()` (macOS 13+)
- Toggle in Settings
- **Effort**: Very Low · **Value**: High — essential for always-on monitoring

### 17. **Multiple Ubuntu Machines**
Support monitoring 2+ Ubuntu devices simultaneously.
- Already partly supported (the API has multi-device)
- Show a device switcher or tabs in the dropdown
- **Effort**: Low · **Value**: Medium (scales with your setup)

---

## 🔒 Security Improvements

### 18. **HTTPS / TLS for Hub**
Encrypt traffic between Mac and Ubuntu.
- Use Let's Encrypt or self-signed cert on the hub
- Tailscale already encrypts traffic, so this is optional but nice
- **Effort**: Medium · **Value**: Medium

### 19. **Token Rotation**
Auto-rotate client tokens every 30 days.
- Hub issues a new token and invalidates the old one
- Mac app handles the renewal transparently
- **Effort**: Medium · **Value**: Low-Medium

---

## 🏆 My Top 5 Recommendations (Best ROI)

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 1 | **Launch at Login** | 15 min | Must-have for daily use |
| 2 | **Quick SSH Button** | 30 min | Saves time every day |
| 3 | **Uptime & Last-Seen** | 1 hour | Peace of mind at a glance |
| 4 | **Top Processes Widget** | 2 hours | Catches problems early |
| 5 | **Historical Sparklines** | 3 hours | See trends, not just numbers |
