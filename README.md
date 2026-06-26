# Metroid Prime Hunters - wiimmfi Player List
A simple tool to see who is connected online and their gamemode/online status.

## How to run (no install needed)

Double-click **`Run MPH Player List.bat`**.

It uses Windows' built-in PowerShell, so nothing extra needs to be installed.
It does require **Chrome** or **Chromium-based Edge** to be present, because
`wiimmfi.de` is now behind a Cloudflare JavaScript challenge — the tool drives a
real browser off-screen to pass the challenge, then reads the stats.

> The original `MPH Wimmfi Player List.ahk` (AutoHotkey v1) used a plain HTTP GET,
> which Cloudflare now blocks (403). `MPH-PlayerList.ps1` is the working port.


Sample Images:

![alt text](https://i.postimg.cc/d0mcdcYR/Sample.png)


![alt text](https://i.postimg.cc/vBYFt2YJ/Sample2.png)
