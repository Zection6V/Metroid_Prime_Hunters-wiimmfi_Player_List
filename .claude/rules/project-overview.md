# プロジェクト概要 — MPH Wiimmfi Player List

`MPH Wimmfi Player List.ahk` の解析ドキュメント。
コード本体ではなく、git 履歴やソースから読み取りにくい「全体像・データの流れ・状態コードの意味」をまとめる。

## これは何か

- **種別**: AutoHotkey **v1** 製のデスクトップ GUI アプリ（単一ファイル `.ahk`）。
- **目的**: 私設 Wii オンラインサービス [Wiimmfi](https://wiimmfi.de) 上で、
  *Metroid Prime Hunters (MPH)* に現在ログインしているプレイヤーと、その
  ゲームモード／オンライン状態を一覧表示する。
- **データ源**: `https://wiimmfi.de/stats/game/mprimeds` の HTML を取得して
  テーブルをスクレイピングする（公式 API ではない）。
- **更新間隔**: 16 秒ごと（`SetTimer, refreshPlayerData, 16000`）。
- **オリジナル作者**: elModo7。本リポジトリはそのプレイヤーリストツール。

> ⚠️ **重要（2026 時点）**: データ源 `wiimmfi.de` は現在 **Cloudflare の JS チャレンジ**
> （"Just a moment..."）で保護されている。AHK 版が使う単純な HTTP GET
> （`WinHttp.WinHttpRequest`）は **403 Forbidden** になり、現状この AHK 版は動かない。
> 追加インストール不要で動かせるよう移植した PowerShell 版を別途用意した
> （[簡単に動かす（インストール不要版）](#簡単に動かすインストール不要版) を参照）。

## 実行時の動作

1. 起動時に `FileInstall` で `img\*.png`・`fonts\*.ttf` を `%A_Temp%` へ展開する
   （コンパイル後の単一 exe でもアイコン／フォントを使えるようにするため）。
2. `CustomFont` クラスで Metroid Prime: Hunters の TTF を読み込み、GUI フォントに適用。
3. キャプションなし・ドラッグ移動可能なカスタム GUI（622x446）を構築。
4. `refreshPlayerData` を即時実行し、以降 16 秒ごとに再取得。
5. `checkMouseStatus` を 100ms ごとに回し、リストボックス上でマウスホイール
   スクロールを有効化する。

## アーキテクチャ / 主要ルーチン

| ラベル / 関数 | 役割 |
|---|---|
| 自動実行部（先頭〜`Return`） | GUI 構築、画像・フォント展開、タイマー設定 |
| `refreshPlayerData:` | HTTP 取得 → HTML テーブルを解析 → `playerData` 構築 → リスト更新 |
| `selectPlayer:` | 選択中プレイヤーの各フィールドを GUI ラベル／画像にデコード表示 |
| `URLToVar(URL)` | `WinHttp.WinHttpRequest.5.1`（COM）で GET し本文文字列を返す |
| `moverVentana:` | `PostMessage 0xA1` でフレームレス窓をドラッグ移動 |
| `GuiEscape:` / `GuiClose:` | アプリ終了 |
| `ControlColor` + `CC_WindowProc` | ListBox の背景／文字色をサブクラス化で着色 |
| `CustomFont` クラス | TTF をファイル／リソースから動的ロード（`AddFontResourceEx` 等） |
| `checkMouseStatus()` + `#If` ホットキー | リストボックス上でのホイール↑↓をカーソル移動に変換 |
| `:*X:em7::` | イースターエッグ（作者名と日付の MsgBox） |

## データ取得とパース（`refreshPlayerData`）

1. ページ HTML 内で `id="online"` を検索。無ければオンライン 0 人とみなす。
2. `tr0` を起点に `</table>` までを切り出し、改行で分割。
3. **1 プレイヤー = 14 行** という前提でループ（`Mod(k,14)`）。各レコードの
   先頭要素はスキップ（`firstElem`）し、残りの `<td>` セルを `curPlayerData` に push。
4. セルから `<td class="dbnull">` / `<td>` / `</td>` を除去し、`&mdash;` を `-` に置換。
5. 完成した配列を `playerData[counter]` に格納（インデックス連番）。
6. 各プレイヤーの **フィールド 11（名前）** を `|` 区切りで ListBox に流し込む。

> 注意: パースは Wiimmfi 側の HTML 構造（列数・`tr0`/`dbnull` クラス名・1 行 14 要素）に
> 強く依存している。ページ仕様が変わると壊れやすい。修正時はまず実際の HTML を確認すること。

## `playerData` フィールドの意味（`selectPlayer` のデコードより）

各プレイヤー配列の主なインデックス：

| index | 内容 | 表示先 |
|---|---|---|
| 3 | フレンドコード | `guiFc` |
| 6 | 複合ステータスコード（`ls_stat`、下記で分解） | 複数 |
| 7 | オンライン状態文字列 | `guiOnlineStatus` |
| 8 | プレイヤー状態コード | `guiPlayerStatus` |
| 11 | プレイヤー名 | `guiPlayerName` / ListBox |

### フィールド 6（`ls_stat`）の分解

値を 7 桁になるまで先頭 `0` 埋め、8 桁未満なら先頭に `1` を付与し、各桁を `StrSplit`。
桁位置（`key`）ごとに意味を持つ：

- **桁 1 — 人数**: `1`→1 人 / `2`→2 人 / `4`→3 人 / `6`→4 人
- **桁 2 — モード**:
  - `0` = Survival / None（survival.png）
  - `1` = Battle / Bounty（battle.png + bounty.png）
  - `2` = Defender / Capture（defender.png + capture.png）
  - `3` = Prime Hunter / Nodes（primehunter.png + nodes.png）
- **桁 7 — Rivals フラグ**: `1` なら Rivals アイコン表示
- **桁 8 — Friends フラグ**: `8` なら Friends アイコン表示
- 桁 7・8 の組み合わせで「Join Players」を Friends Only / Rivals Only / Friends and Rivals と表示

### フィールド 7（オンライン状態文字列）

- `o` = Online
- `og` = Guest of Room
- `oGv` = In Game
- `oGvS` = Searching for Game

### フィールド 8（プレイヤー状態コード）

- `1` = Online / `2` = Guest Room / `3` = Searching Opponents / `5` = Joining Game / `6` = Hosting Game
- 加えて `ls_stat = 0` のときの特例:
  - `8 = 6` → In-Game (Host)（人数・モードは Unknown）
  - `8 = 2` → In-Game (Client)（同上）

## 依存・前提

- **AutoHotkey v1**（v2 では動かない構文）。
- Windows 専用（`WinHttp` COM、`gdi32`/`AddFontResourceEx` などの DllCall）。
- `img/`・`fonts/` ディレクトリが `FileInstall` のソースとして必要（ビルド時）。
- 実行時にネットワーク到達性（wiimmfi.de）が必要。

## 簡単に動かす（インストール不要版）

AHK 版が Cloudflare で動かなくなったため、**Windows 標準の PowerShell + WinForms** で
再実装した移植版を同梱している。追加インストールは不要。

| ファイル | 役割 |
|---|---|
| `MPH-PlayerList.ps1` | 本体。Chrome/Edge を CDP 経由で操作してデータ取得 → 解析 → GUI 表示 |
| `Run MPH Player List.bat` | ダブルクリック用ランチャー（`powershell -STA` で `.ps1` を起動） |

### 使い方

1. `Run MPH Player List.bat` をダブルクリックするだけ。
2. 初回は Cloudflare 通過のため数秒〜十数秒待つ（"Connecting..." 表示）。
3. 16 秒ごとに自動更新。プレイヤーを選ぶと詳細（FC・状態・モード等）を表示。

### 依存・前提

- Windows + **PowerShell 5.1**（OS 標準）。
- **Chrome** もしくは **Chromium 版 Edge** のいずれか（OS にほぼ標準で存在 / 追加導入不要）。
  どちらも無い場合のみエラーダイアログを出す。

### Cloudflare をどう突破しているか

- 単純 GET は 403。そこで **PC のブラウザを「非ヘッドレス・画面外」で起動**し、
  **DevTools Protocol(CDP)** に接続。ブラウザ自身が JS チャレンジを通過して
  `cf_clearance` Cookie を得る（ヘッドレスは検知され通らないため非ヘッドレス）。
- 通過後は、同一オリジンの **ページ内 `fetch()`** を CDP の `Runtime.evaluate` で実行し、
  チャレンジ無しの生 HTML を取得する（毎回ナビゲーションし直さず軽量）。
- 取得 HTML の `<table id="online">` を正規表現で行→セル分解。AHK 版の「14 行＝1 名」
  決め打ちより堅牢。終了時に起動したブラウザを確実に kill する。

### HTML 構造（移植時に確認した実データ）

`<table id="online">` の列順は **12 列**:
`id4 / pid / fc / host / gid / ls_stat / ol_stat / status / suspend / n / name1 / name2`。
0 始まりで `fc=[2]`, `ls_stat=[5]`, `ol_stat=[6]`, `status=[7]`, `name1=[10]`
（AHK 版の 1 始まりインデックス 3/6/7/8/11 に対応）。状態コードの意味は上表のとおり。

### 診断モード

`powershell -File "MPH-PlayerList.ps1" -SelfTest` で GUI を出さずに
取得〜解析〜描画更新を 1 回だけ実行し、`%TEMP%\mph_selftest.log` に結果を書く。

## 改修時の注意点

- パースは HTML 構造依存。Wiimmfi 側変更で空表示・誤表示になり得る → 実 HTML で要確認。
- 状態コード（フィールド 6/7/8）のマッピングはこのドキュメントが一次資料。
  ロジック変更時はここも更新する。
- 画像・フォントを追加したら `FileInstall` 行と `img/`・`fonts/` の両方を揃える。
- AHK v1 構文を維持すること（v2 への移行は別タスク）。
