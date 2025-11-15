# 新規ユーザー利用手順（利用者用）

この手順で、あなたのPC/機器のローカルサービスをインターネットから安全に利用できるようにします。外側はHTTPS（CaddyでTLS終端）、内側はFRPで中継します。

事前に受け取るもの（管理者から）
- デバイスID（サブドメイン）例: `pc001-web`
- FRPトークン（長いランダム文字列）

要件
- OS: macOS / Linux / Windows いずれか
- 外向きネットワークから `kimulabfrp.jp:7000/tcp` へ到達できること
  - 到達性テスト（任意）: `nc -vz kimulabfrp.jp 7000`
- 学内/社内プロキシ環境ではプロキシURL（例: `http://proxy.example:3128`）

1) frpc を入手
- 公式リリース: https://github.com/fatedier/frp/releases （v0.61.0）
- バイナリ名: `frpc`（Windowsは `frpc.exe`）
- 任意のフォルダに配置（macOS/Linuxでは実行権限を付与）

2) ローカルサービスを準備
- 例: 8000番でテストHTTPを起動（任意のディレクトリで）
  - macOS/Linux: `python3 -m http.server 8000`
  - Windows(PowerShell): `python -m http.server 8000`
- 既存アプリがあれば、そのポート番号を覚えておく（例: 8000）

3) frpc 設定ファイル（frpc.toml）
以下を `frpc.toml` として保存します。`<FRP_TOKEN>` と `<your-id>`、`localPort` をあなたの値に置き換えてください。
```
serverAddr = "kimulabfrp.jp"
serverPort = 7000
protocol   = "tcp"

[auth]
method = "token"
token  = "<FRP_TOKEN>"

[transport]
# frps は生TLS(--tls-only) なので frpc は TLS を有効化
# 自己署名の場合の暫定: insecureSkipVerify=true
# 運用でCA整備後は false へ
 tls = { enable = true, insecureSkipVerify = true }
# プロキシ必須なら有効化（例）
# proxyURL = "http://proxy.example:3128"

[[proxies]]
name      = "<your-id>"
type      = "http"
localPort = 8000
subdomain = "<your-id>"
```

4) frpc を起動
- macOS/Linux: `./frpc -c frpc.toml`
- Windows: `frpc.exe -c frpc.toml`
- 期待ログ: `login to server success` / `start proxy success`

5) 動作確認（外部から）
- ブラウザ/CLI: `https://<your-id>.kimulabfrp.jp`
  - ローカルのHTTP応答が表示されれば成功
- サーバ側（管理者確認）: frpsログに `http proxy listen for host [<your-id>.kimulabfrp.jp]`

6) 代表的なトラブル
- 404 が返る
  - frpc未接続 / `subdomain` の綴り違い / ローカルポート未起動
- `unexpected EOF`（frpc）
  - frpcの `protocol=tcp` + `[transport].tls.enable=true` を確認
  - 7000到達性: `nc -vz kimulabfrp.jp 7000`
  - 必要なら `[transport].proxyURL` を設定
- TLS エラー（ブラウザ）
  - 初回は証明書発行待ち（数十秒〜1分）。解消しない場合は管理者へ連絡

7) 常時起動（任意）
- Linux (systemd)
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
- macOS (launchd; 例)
```
~/Library/LaunchAgents/com.kimulab.frpc.plist
ProgramArguments: [/path/to/frpc, -c, /path/to/frpc.toml]
RunAtLoad: true, KeepAlive: true
```

8) セキュリティ注意
- 認証情報（トークン）は第三者と共有しない
- 公開するディレクトリ/アプリに機密ファイルを置かない
- 利用が終わったら frpc を停止

不明点や問題は管理者まで連絡してください（`<your-id>`, 実行時刻, エラーメッセージを添えて）。
