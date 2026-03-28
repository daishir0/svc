# svc - Interactive systemctl Controller

## Overview

An interactive terminal-based systemctl controller with arrow key navigation. Manage your custom systemd services with minimal keystrokes — start, stop, restart, view logs, manage timers, and delete services all from a single TUI.

### Key Features

- **Arrow Key Navigation** — Navigate with arrow keys and Enter. No need to type service names or numbers.
- **Service Management** — Start, stop, restart, enable/disable auto-start, view status and logs.
- **Timer Integration** — View and control associated `.timer` units. Displays schedule definitions (OnCalendar) inline.
- **Port Display** — Shows listening TCP/UDP ports for active services.
- **Service Deletion** — Press `d` or `Delete` to remove a service (with confirmation). Automatically removes associated timers.
- **Status-sorted List** — Services sorted by state: active → failed → inactive.
- **Scrollable** — PageUp/PageDown support for long service lists.

### Screenshot

```
===== svc - Service Controller =====
8 services

  ▶ my-webapp.service                  [active]  :3000
    api-server.service                 [active]  :8080,8443
    background-worker.service          [active]
    my-app.service                     [failed]
    data-sync.service                  [inactive] ⏱running *-*-* 05:00:00
    backup.service                     [inactive] ⏱running Tue *-*-* 03:00:00
    log-rotate.service                 [inactive] ⏱enabled *-*-* 02:00:00
    monitoring.service                 [inactive]

  ↑↓:move Enter:select d:delete ESC/q:quit
```

```
--- my-webapp.service [active] [enabled] ---

  ▶ stop
    restart
    status
    log
    disable (auto-start OFF)
    back

  ↑↓:move Enter:select ESC/q:back
```

## Prerequisites

- Linux with systemd
- Bash 4.0+
- `ss` command (iproute2)

## Installation

```bash
# 1. Clone the repository
git clone https://github.com/daishir0/svc.git
cd svc

# 2. Make executable
chmod +x svc.sh

# 3. (Optional) Add alias to ~/.bashrc
echo 'svc() { /path/to/svc/svc.sh "$@"; }' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```bash
# Interactive mode — browse all services
svc

# Direct mode — jump to a specific service
svc nginx
svc my-webapp
```

### Controls

| Key | Action |
|-----|--------|
| ↑ / ↓ | Move cursor |
| Enter | Select |
| PageUp / PageDown | Scroll page |
| d / Delete | Delete service (list screen) |
| ESC / q | Go back / Quit |

### Available Actions

| Action | Description |
|--------|-------------|
| start | Start the service |
| stop | Stop the service |
| restart | Restart the service |
| status | Show service status (top 20 lines) |
| log | Show recent journal logs (last 50 lines) |
| enable / disable | Toggle auto-start on boot |
| timer start/stop | Start or stop associated timer |
| timer status | Show timer status and next trigger time |

### Configuration

Edit the top of `svc.sh` to customize the exclude list:

```bash
# Exclude patterns (regex) — services matching these won't appear in the list
EXCLUDE_PATTERNS="^dbus|^ttyd|^firewalld"
```

### Service Source

Only services in `/etc/systemd/system/` are listed (user-created services). Vendor/system services from `/usr/lib/systemd/system/` are excluded by design.

## Notes

- `sudo` is required for start/stop/restart/enable/disable/delete operations.
- Port display only works for active services (inactive services have no running process).
- Timer schedule is read directly from the `.timer` unit file (`OnCalendar`, `OnBootSec`, etc.).

## License

MIT License

---

# svc - 対話型systemctlコントローラ

## 概要

矢印キーで操作できる対話型のsystemctlコントローラです。自作のsystemdサービスを最小のキー操作で管理できます。起動・停止・再起動・ログ閲覧・タイマー管理・削除をひとつのTUIで完結します。

### 主な機能

- **矢印キー操作** — ↑↓キーとEnterだけで操作可能。サービス名を打つ必要なし。
- **サービス管理** — 起動、停止、再起動、自動起動ON/OFF、ステータス・ログ閲覧。
- **タイマー統合** — 関連する`.timer`ユニットの表示と制御。スケジュール定義（OnCalendar）をインライン表示。
- **ポート表示** — activeなサービスのリスニングTCP/UDPポートを表示。
- **サービス削除** — `d`キーまたは`Delete`キーで削除（確認あり）。関連タイマーも自動削除。
- **状態順ソート** — active → failed → inactive の順に表示。
- **スクロール対応** — PageUp/PageDownでページ送り。

### 画面イメージ

```
===== svc - サービスコントローラ =====
8個のサービス

  ▶ my-webapp.service                  [active]  :3000
    api-server.service                 [active]  :8080,8443
    background-worker.service          [active]
    my-app.service                     [failed]
    data-sync.service                  [inactive] ⏱running *-*-* 05:00:00
    backup.service                     [inactive] ⏱running Tue *-*-* 03:00:00
    log-rotate.service                 [inactive] ⏱enabled *-*-* 02:00:00
    monitoring.service                 [inactive]

  ↑↓:移動 Enter:選択 d:削除 ESC/q:戻る
```

```
--- my-webapp.service [active] [enabled] ---

  ▶ stop
    restart
    status
    log
    disable (自動起動OFF)
    戻る

  ↑↓:移動 Enter:選択 ESC/q:戻る
```

## 前提条件

- systemd搭載のLinux
- Bash 4.0以上
- `ss` コマンド（iproute2）

## インストール

```bash
# 1. リポジトリをクローン
git clone https://github.com/daishir0/svc.git
cd svc

# 2. 実行権限を付与
chmod +x svc.sh

# 3.（任意）~/.bashrc にエイリアスを追加
echo 'svc() { /path/to/svc/svc.sh "$@"; }' >> ~/.bashrc
source ~/.bashrc
```

## 使い方

```bash
# 対話モード — 全サービスを表示
svc

# 直接指定 — 特定サービスのアクション画面へ直行
svc nginx
svc my-webapp
```

### 操作キー

| キー | 動作 |
|------|------|
| ↑ / ↓ | カーソル移動 |
| Enter | 選択・実行 |
| PageUp / PageDown | ページ送り |
| d / Delete | サービス削除（リスト画面） |
| ESC / q | 戻る・終了 |

### アクション一覧

| アクション | 説明 |
|-----------|------|
| start | サービス起動 |
| stop | サービス停止 |
| restart | サービス再起動 |
| status | ステータス表示（上位20行） |
| log | 直近のジャーナルログ（最新50行） |
| enable / disable | ブート時の自動起動ON/OFF |
| timer start/stop | 関連タイマーの起動・停止 |
| timer status | タイマーのステータスと次回実行時刻を表示 |

### 設定

`svc.sh` の上部で除外リストをカスタマイズできます:

```bash
# 除外パターン（正規表現）— マッチしたサービスはリストに表示されません
EXCLUDE_PATTERNS="^dbus|^ttyd|^firewalld"
```

### サービスの取得元

`/etc/systemd/system/` にあるサービスのみが一覧表示されます（ユーザー作成のサービス）。`/usr/lib/systemd/system/` のベンダー・システムサービスは対象外です。

## 注意事項

- 起動/停止/再起動/enable/disable/削除には `sudo` が必要です。
- ポート表示はactiveなサービスのみ対応（inactiveはプロセスが動いていないため取得不可）。
- タイマーのスケジュールは`.timer`ユニットファイル（`OnCalendar`、`OnBootSec`等）から直接読み取ります。

## ライセンス

MIT License
