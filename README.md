# Metroid Prime Hunters - Wiimmfi / WiiLink Player List

A Windows PowerShell viewer for checking Metroid Prime Hunters players, rooms, game modes, and online status on Wiimmfi and WiiLink WFC.

## How to run

No installation is required. Double-click one of the included launchers:

| Launcher | Shows |
|---|---|
| **`Run MPH Unified.bat`** | Wiimmfi and WiiLink side-by-side |
| **`Run Wiimmfi Player List.bat`** | Wiimmfi only |
| **`Run WiiLink Player List.bat`** | WiiLink WFC only |

The polling interval can be changed between 15 seconds, 30 seconds, 1 minute, 2 minutes, and 5 minutes. The default is 30 seconds. Use **Refresh** for an immediate update.

## Languages

The GUI supports:

- Japanese
- English
- German
- French
- Italian
- Spanish

The Windows UI language is detected automatically. It can be overridden with:

```cmd
set MPH_LANG=ja
```

Supported values are `ja`, `en`, `de`, `fr`, `it`, and `es`.

## Server transports

### Wiimmfi

Wiimmfi is protected by a Cloudflare JavaScript challenge. The viewer starts Chrome or Chromium-based Edge off-screen, passes the challenge, and reads the lightweight `/text` endpoint.

### WiiLink WFC

WiiLink supports two selectable transports:

- **Chrome / Edge** — the default; requests the API through a browser session
- **Direct API** — optional manual mode; requests the JSON API without opening a browser

The browser transport is useful when local security software, TLS interception, or a network proxy blocks direct PowerShell requests.

Both WiiLink requests are restricted to Metroid Prime Hunters with `?game=mprimeds`:

- `https://api.wfc.wiilink24.com/api/stats?game=mprimeds`
- `https://api.wfc.wiilink24.com/api/groups?game=mprimeds`

WiiLink only exposes a room in the room list when at least two players are present. Therefore, the online count can be greater than zero while no room row is available. The viewer also displays this rule directly above the WiiLink room list.

## WiiLink proxy support

Direct API mode no longer disables the Windows proxy globally. With no configuration, it uses the following automatic fallback order:

1. Direct connection
2. `HTTPS_PROXY` or `HTTP_PROXY`, unless the host is covered by `NO_PROXY`
3. Windows system proxy, including PAC/WPAD configurations

The detailed diagnostic log records the route plan, each timeout or connection error, and the route that succeeded. Expand the log panel and enable **Details** to see entries with the `PROXY` stage.

### Force a specific route

Set `MPH_PROXY` before starting the viewer:

```cmd
rem Automatic fallback; this is the default
set MPH_PROXY=auto

rem Windows system proxy only
set MPH_PROXY=system

rem Direct connection only
set MPH_PROXY=direct

rem HTTPS_PROXY / HTTP_PROXY only
set MPH_PROXY=environment

rem Explicit proxy server
set MPH_PROXY=http://proxy.example.com:8080
```

For an authenticated proxy, Windows credentials are used automatically. Explicit credentials can be supplied when required:

```cmd
set MPH_PROXY_USERNAME=username
set MPH_PROXY_PASSWORD=password
set MPH_PROXY_DOMAIN=DOMAIN
```

Do not include credentials when sharing diagnostic logs.

### Timeout settings

In automatic mode, the initial direct probe is intentionally short so a required proxy can be tried quickly.

```cmd
rem Direct probe; default 6 seconds
set MPH_DIRECT_TIMEOUT_SEC=10

rem Environment/system/custom proxy attempt; default 20 seconds
set MPH_HTTP_TIMEOUT_SEC=30
```

When Direct API still fails, use the default **Chrome / Edge** transport. Browsers often support enterprise PAC files and authentication mechanisms that are unavailable to PowerShell networking APIs.

## Diagnostic logs

The unified viewer can show:

- All logs
- Wiimmfi only
- WiiLink only
- Application events only

Standalone viewers reuse the same diagnostic log component. Normal updates append only newly received entries instead of clearing and rebuilding the entire log. Auto-scroll moves from the currently rendered content to the latest entry, reducing flicker. When auto-scroll is disabled, the current position is preserved.

Detailed logging also includes:

- WiiLink `stats.raw.json`
- WiiLink `groups.raw.json`
- Wiimmfi `wiimmfi.text.raw`

Raw payload logging is limited to 262,144 characters per response by default. Change the limit with:

```cmd
set MPH_LOG_PAYLOAD_MAX_CHARS=1000000
```

Use `0` for no limit. Raw payloads may contain player names, friend codes, PIDs, or other session data, so review copied logs before sharing them publicly.

## Project layout

```text
program/lib/WiimmfiSource.ps1      Wiimmfi browser/CDP acquisition and parsing
program/lib/WiiLinkSource.ps1      WiiLink transport orchestration and parsing
program/lib/ProxyHttp.ps1          Direct/environment/system proxy routing and fallback
program/lib/PayloadLog.ps1         Raw response metadata, chunking, and limits
program/lib/LogStore.ps1           Source-separated diagnostic storage and filtering
program/lib/DiagnosticLogView.ps1  WinForms diagnostic rendering
program/lib/TreeRender.ps1         Shared player/room TreeView rendering
program/lib/ViewerCommon.ps1       Shared theme, controls, and poll-worker utilities
program/lib/I18n.ps1               GUI localization and status-code maps
program/MPH-Unified.ps1            Combined viewer
program/Wiimmfi-PlayerList.ps1     Wiimmfi-only viewer
program/WiiLink-PlayerList.ps1     WiiLink-only viewer
```

## Legacy implementation

The original `MPH Wimmfi Player List.ahk` used a plain HTTP request. Cloudflare now blocks that approach, so the PowerShell viewers are the maintained implementation.

## Screenshots

![Unified viewer](https://i.postimg.cc/d0mcdcYR/Sample.png)

![Player details](https://i.postimg.cc/vBYFt2YJ/Sample2.png)
