# エンドユーザー向け 利用ガイド（FRP 中継 + InfluxDB）

対象
- 学内/社内の機器やアプリを、インターネットから安全に利用したい方
- 計測データを InfluxDB に保存・閲覧したい方

概要
- 入口ドメイン: `kimulabfrp.jp`
- サービスURL: `http://<機器ID>.kimulabfrp.jp`
- データ基盤: `https://influx.kimulabfrp.jp`（管理者から配布されるユーザー/トークンで利用）

注意
- 公開中の各サービスの可用性・認証は、担当者の運用方針に従います
- このガイドの手順は標準的な流れです。個別の指示がある場合はそちらを優先してください

---

## 1. 公開されたサービスを使う（閲覧側）

- サービスURLは `http://<機器ID>.kimulabfrp.jp` 形式です
  - 例: `http://test.kimulabfrp.jp`
- WebSocketも同じURLで利用できます（アプリがWS対応の場合）
- 404 が返る場合
  - 機器が未接続（frpc未起動）
  - または機器側サービスが停止中
  - 担当者へ連絡してください

---

## 2. 自分の機器を公開する（提供側）

機器側に FRP クライアント（frpc）を常時起動します。機器はアウトバウンド通信のみでOKです。

準備
- 管理者から以下を受け取ります
  - 機器ID（サブドメイン名）: 例 `test`
  - frp token（長いランダム文字列）
  - 公開したいローカルポート番号（例 `8000`）
- OS: Ubuntu を想定（他OSでも frpc は動作します）

方法A（推奨・Ubuntu）: セットアップスクリプト
- このリポジトリの `scripts/install_frpc_ubuntu.sh` を使います
- 例（機器ID=test, ローカルポート=8000）
  - `sudo bash scripts/install_frpc_ubuntu.sh -d test -p 8000 -t 'YOUR_FRP_TOKEN'`
- 学内プロキシ経由が必要な場合
  - `--proxy-url 'http://proxy.example:3128'` を追加
- 確認
  - `curl -I http://test.kimulabfrp.jp` → 200 が返れば公開成功

方法B（手動）: 最小手順（Linux）
1) frpc を入手
- https://github.com/fatedier/frp/releases から `frpc` バイナリ（v0.61.0）をダウンロード
- `/usr/local/bin/frpc` に配置して実行可能化

2) 設定 `/etc/frp/frpc.toml`
```
serverAddr = "kimulabfrp.jp"
serverPort = 7000
protocol   = "wss"

[auth]
method = "token"
token  = "YOUR_FRP_TOKEN"

[[proxies]]
name      = "test"        # ←あなたの機器ID
type      = "http"
localPort = 8000          # ←公開したいローカルポート
subdomain = "test"        # ←あなたの機器ID
```

3) 起動（1回だけ）
- `frpc -c /etc/frp/frpc.toml`

4) 常駐（systemd）
```
[Unit]
Description=frpc
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```
- `sudo systemctl enable --now frpc`

トラブルシュート（提供側）
- `unexpected EOF`: サーバ側TLSと不一致、またはネットワーク遮断。管理者へ連絡
- 404: 機器未接続 or ローカルアプリ停止。frpcログ/アプリの起動状態を確認
- プロキシ配下: `--proxy-url` を指定（HTTP/HTTPS/SOCKS5）

---

## 3. 計測データを扱う（InfluxDB）

入口
- UI: `https://influx.kimulabfrp.jp`
- 認証: 管理者配布のユーザー/パスワード、トークン

ヘルスチェック
- `curl -I https://influx.kimulabfrp.jp/health` → 204 ならOK

書き込み（Line Protocol、例）
- エンドポイント: `POST /api/v2/write?org=kimulab&bucket=IoT&precision=ns`
- ヘッダ: `Authorization: Token <YOUR_TOKEN>`
```
# 計測名,タグ key=value フィールド key=value タイムスタンプ(ns)
piezo,sensor=A value=0.12 1731139200000000000
solar,unit=W value=23.5  1731139201000000000
capacitor,node=X value=3.3 1731139202000000000
```

クエリ（Flux、例）
- エンドポイント: `POST /api/v2/query`
- ヘッダ: `Authorization: Token <YOUR_TOKEN>`, `Content-Type: application/vnd.flux`
```
from(bucket:"IoT")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "piezo")
  |> limit(n: 10)
```

既定ポリシー（参考）
- バケット: `IoT`
- リテンション: 90日

---

## 4. よくある質問（FAQ）

- Q: `http://<ID>.kimulabfrp.jp` が404
  - A: 機器が未接続/停止。担当者に連絡、または frpc とローカルアプリを確認
- Q: WebSocketは使える？
  - A: はい。同じURLで透過します（アプリ側がWS対応であること）
- Q: HTTPS 強制ですか？
  - A: エッジの一般公開はHTTP、InfluxDBはHTTPSです（セキュリティ方針により変更される場合あり）
- Q: トークンが分かりません
  - A: 管理者から配布されます。第三者に共有しないでください

---

## 5. 連絡先 / サポート
- 障害・設定変更・機器追加の申請は管理者（運用担当）まで
- 伝えてほしい情報
  - 機器ID（希望のサブドメイン）
  - ローカルポート
  - 必要な公開範囲や制限（あれば）
  - InfluxDB の権限（読み取り/書き込み）

以上
