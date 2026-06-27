# Metroid Prime Hunters - wiimmfi Player List
A simple tool to see who is connected online and their gamemode/online status.

## How to run (no install needed)

Two services are supported. Both use Windows' built-in PowerShell, so nothing
extra needs to be installed.

### Wiimmfi — double-click `Run MPH Player List.bat`
Shows players on **wiimmfi.de**. It requires **Chrome** or **Chromium-based Edge**
to be present, because `wiimmfi.de` is now behind a Cloudflare JavaScript
challenge — the tool drives a real browser off-screen to pass the challenge,
then reads the stats.

> The original `MPH Wimmfi Player List.ahk` (AutoHotkey v1) used a plain HTTP GET,
> which Cloudflare now blocks (403). `MPH-PlayerList.ps1` is the working port.

### WiiLink WFC — double-click `Run WiiLink Player List.bat`
Shows rooms/players on **WiiLink WFC** (`wfc.wiilink24.com`). This one needs
**no browser at all** — WiiLink exposes a plain JSON API, so it just makes HTTP
requests. Rooms are shown as a tree (room → players); select a node for details.


Sample Images:

![alt text](https://i.postimg.cc/d0mcdcYR/Sample.png)


![alt text](https://i.postimg.cc/vBYFt2YJ/Sample2.png)
