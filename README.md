# Metroid Prime Hunters - wiimmfi Player List
A simple tool to see who is connected online and their gamemode/online status.

## How to run (no install needed)

Three viewers are provided. All use Windows' built-in PowerShell, so nothing
extra needs to be installed. Each viewer lets you pick the polling interval
(15s / 30s / 1m / 2m / 5m, default 30s — gentle on the servers).

| Double-click | Shows |
|---|---|
| **`Run MPH Unified.bat`** | Both servers side-by-side in one window |
| **`Run Wiimmfi Player List.bat`** | Wiimmfi only |
| **`Run WiiLink Player List.bat`** | WiiLink WFC only |

- **Wiimmfi** (`wiimmfi.de`) is behind a Cloudflare JavaScript challenge, so it
  requires **Chrome** or **Chromium-based Edge**: the tool drives a real browser
  off-screen to pass the challenge, then reads the lightweight `/text` endpoint.
- **WiiLink WFC** (`wfc.wiilink24.com`) needs **no browser** — it exposes a plain
  JSON API. Rooms are shown as a tree (room → players); expand a node for details.

> The original `MPH Wimmfi Player List.ahk` (AutoHotkey v1) used a plain HTTP GET,
> which Cloudflare now blocks (403). The PowerShell viewers are the working ports.

### Project layout (SRP)

```
lib/WiimmfiSource.ps1   data fetch — Wiimmfi (browser/CDP + /text parsing)
lib/WiiLinkSource.ps1   data fetch — WiiLink (JSON API)
lib/TreeRender.ps1      presentation — shared TreeView rendering
lib/ViewerCommon.ps1    UI parts — theme, top bar + interval, tree panel, poll worker
MPH-Unified.ps1         viewer — both servers
Wiimmfi-PlayerList.ps1  viewer — Wiimmfi only
WiiLink-PlayerList.ps1  viewer — WiiLink only
```


Sample Images:

![alt text](https://i.postimg.cc/d0mcdcYR/Sample.png)


![alt text](https://i.postimg.cc/vBYFt2YJ/Sample2.png)
