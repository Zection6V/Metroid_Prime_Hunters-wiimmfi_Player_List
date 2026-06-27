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

### フィールド 7（ol_stat / オンライン状態フラグ文字列）

ol_stat は **1 文字ずつ意味を持つフラグ列**（例 `oGvS` = 4 つの状態の合成）。
PowerShell 版（`WiimmfiSource.ps1` の `ConvertTo-WiimmfiPlayer`）は、Tampermonkey 版
"Wiimfi MPH Stats Translator JP" を参考に各文字を**日本語化して ＋ で連結**する。
大文字小文字を区別する（`G`=グローバル と `g`=ゲスト、`C`=ルーム接続中 と `c`=リージョン）
ため `switch -CaseSensitive` を使う。

| 文字 | 意味 | 文字 | 意味 |
|---|---|---|---|
| `o` | オンライン | `g` | ゲスト |
| `P` | プライベートルーム | `v` | 観戦者 |
| `G` | グローバル | `S` | グローバル検索中 |
| `c` | リージョン | `C` | ルーム接続中 |
| `w` | ワールドワイド | `A` | アクティブ |
| `h` | ホスト | `R` / `B` | レース / バトル |

例: `oGvS` → 「オンライン＋グローバル＋観戦者＋グローバル検索中」

### フィールド 8（status / プレイヤー状態コード）

数値を日本語化（`$script:WiimmfiStatusMap`）:

- `0` = オフライン / `1` = オンライン（待機中）/ `2` = ルーム/グローバルのゲスト
- `3` = グローバル検索中 / `4` = プライベートルーム接続中
- `5` = ルーム/グローバルのホスト / `6` = ホスト

> 旧 AHK 版は英語かつ `ls_stat=0` の In-Game 特例を持っていたが、char 単位の ol_stat
> デコードで状態が十分表現できるため、PowerShell 版では特例を廃し上記マップに統一した。

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
| `Wiimmfi-PlayerList.ps1` | 本体。Chrome/Edge を CDP 経由で操作してデータ取得 → 解析 → GUI 表示 |
| `Run Wiimmfi Player List.bat` | ダブルクリック用ランチャー（`powershell -STA` で `.ps1` を起動） |

### 使い方

1. `Run Wiimmfi Player List.bat` をダブルクリックするだけ。
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

`powershell -File "Wiimmfi-PlayerList.ps1" -SelfTest` で GUI を出さずに
取得〜解析〜描画更新を 1 回だけ実行し、`%TEMP%\mph_selftest.log` に結果を書く。

## WiiLink WFC 版（別サービス対応）

wiimmfi とは別の私設サービス **WiiLink WFC**（`wfc.wiilink24.com`）向けの移植版も同梱。

| ファイル | 役割 |
|---|---|
| `WiiLink-PlayerList.ps1` | 本体。JSON API を直接叩いて取得 → ルーム/プレイヤーをツリー表示 |
| `Run WiiLink Player List.bat` | ダブルクリック用ランチャー |

### wiimmfi 版との違い

- **ブラウザ不要**。WiiLink は Cloudflare 等の保護が無く、公式 JSON API を素の
  HTTP GET で取得できる（CDP 経由が必要だった wiimmfi 版より大幅に軽量）。
- **データモデルがルーム中心**。プレイヤーは「グループ（ルーム）」に属する。
  そのため GUI は ListBox ではなく **TreeView（ルーム → プレイヤー）**。

### データ源（JSON API）

- `https://api.wfc.wiilink24.com/api/stats` — 全ゲームの集計
  `{ "global": {...}, "mprimeds": { "online", "active", "groups" }, ... }`
- `https://api.wfc.wiilink24.com/api/groups` — ルーム配列。`game == "mprimeds"` で絞る。

各 group（ルーム）の構造:

| フィールド | 意味 |
|---|---|
| `id` | ルーム ID（例 `VFZRTO`） |
| `created` | 作成時刻（ISO8601 / UTC） |
| `type` | `anybody`→**Public** / `private`→**Friends** |
| `suspend` | `true`→**Not joinable** / `false`→**Joinable** |
| `host` | ホストの players キー（例 `"0"`） |
| `players` | `"0","1",...` をキーにしたオブジェクト |

各 player の構造: `name` / `fc`（フレンドコード）/ `pid` / `count` / `conn_fail` /
`conn_map` / `suspend`。（`ev`=VR・`eb`=BR は Mario Kart 用で MPH には無い）

> 補足: ページ `wfc.wiilink24.com/online/mprimeds` 自体はデータを含まず、
> `/js/online_updater.js` が上記 API を 30 秒ごとに取得して描画している。
> 本ツールはその API を直接叩く（15 秒間隔）。

### 高パフォーマンス / 非ブロッキング設計（両版共通）

ネットワーク取得は **別 runspace（バックグラウンドスレッド）** で実行し、結果を
同期ハッシュテーブル経由で受け渡す。UI は 250ms の軽量タイマーで新着のみ拾って
描画するため、取得中も**ウィンドウが固まらない**。さらに、前回と内容が変わらない
ときは ListBox / TreeView を作り直さず、選択・展開状態を保持する。
`-SelfTest` を付けると GUI 無しで取得〜解析〜描画更新を実行しログ出力する。

## 現在のアーキテクチャ（3 ビューワ + 共有ライブラリ / SRP）

情報取得・描画・画面進行を責務分離（SRP）し、3 つのビューワが同じライブラリを使う。

```
lib/WiimmfiSource.ps1   データ取得：Wiimmfi（ブラウザ/CDP で Cloudflare 通過 → /text 解析）
lib/WiiLinkSource.ps1   データ取得：WiiLink（JSON API）
lib/TreeRender.ps1      表示：TreeView 描画（Update-WiimmfiTree / Update-WiiLinkTree）
lib/ViewerCommon.ps1    UI 共通部品：配色テーマ・上部バー(間隔セレクタ)・ツリーパネル・
                        ステータスバー・ワーカー基盤（Get-MphTheme / New-TopBar /
                        New-TreePanel / New-StatusBar / Start-PollWorker / Stop-PollWorker）
MPH-Unified.ps1         ビューワ：両サーバを 1 画面（左右 2 ペイン）
Wiimmfi-PlayerList.ps1  ビューワ：Wiimmfi 専用
WiiLink-PlayerList.ps1  ビューワ：WiiLink 専用
```

- 各ビューワは lib を dot-source し、UI 部品を組み立てるだけの薄い「画面」。取得・描画・
  UI 部品・ワーカー生成のロジックはすべて lib 側にあり重複は無い。
- **ポーリング間隔を UI で選択可能**（15s/30s/1m/2m/5m、既定 30 秒）。`$sync.IntervalMs`
  をワーカーが参照。未接続中のみ 3 秒間隔で素早く再試行し、通過後は選択間隔に従う。
- **↻ Refresh ボタン**で即時更新。`$sync.<...>Refresh` フラグを立てると、ワーカーの待機
  ループが残り時間を打ち切って直ちに再取得する（ポーリングを増やさず待機をスキップ
  するだけなのでサーバ負荷は増えない）。統合ビューワは 1 ボタンで両サーバを更新。
- 取得は各サーバごとの**別 runspace**。lib を `. $sync.WiimmfiLib` 等で読み込んで実行。
  UI は 300ms タイマーで `$sync` を監視し、Seq 変化かつ内容変化時のみ TreeView を再構築。
- 統合ビューワは `TableLayoutPanel`(50/50) + Dock でレスポンシブ。横スクロール無し。
- いずれのビューワも `-SelfTest` で GUI 無しの 1 回実行ログ（`%TEMP%\*_selftest.log`）。

### Wiimmfi の軽量 text エンドポイント

データ取得は HTML スクレイピングをやめ、`https://wiimmfi.de/stats/game/mprimeds/text`
を使う（同じく Cloudflare 下なので取得は CDP 経由）。形式は 1 行目が `!` 区切りヘッダ、
以降が `|` 区切りのプレイヤー行（列順は HTML 版と同じ 12 列）。HTML（約 8KB）より
遥かに軽量（約 100B）で、解析も `|` 分割で堅牢。オンライン 0 人のとき本文は空。
> 通過判定: 応答が Cloudflare チャレンジ（`Just a moment` / `<html`）なら未通過として
> `$null` を返す。空文字は「0 人の正常応答」として扱う。

### Mii 名の文字化け対策（WiiLink/Wiimmfi 共通）

WiiLink API は Content-Type に charset を持たず、PS 5.1 の `Invoke-WebRequest.Content`
は ISO-8859-1 で誤デコードして和文 Mii 名が壊れる。生バイトを
`[Text.Encoding]::UTF8.GetString()` で明示デコードして回避。TreeView は等幅かつ和文
対応の **MS Gothic** を使用。

> 補足: 旧 `img/`（モードアイコン）と `fonts/` は、ツリー表示ビューワでは不要のため削除済み。

## 改修時の注意点

- パースは HTML 構造依存。Wiimmfi 側変更で空表示・誤表示になり得る → 実 HTML で要確認。
- 状態コード（フィールド 6/7/8）のマッピングはこのドキュメントが一次資料。
  ロジック変更時はここも更新する。
- 画像・フォントを追加したら `FileInstall` 行と `img/`・`fonts/` の両方を揃える。
- AHK v1 構文を維持すること（v2 への移行は別タスク）。
