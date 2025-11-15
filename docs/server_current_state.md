# 現行サーバー設計・状態まとめ (2025-11-09)

目的
- 外部からの HTTP/WS リクエストを、FRP (frps+frpc) を使って社内/宅内機器へ中継する。
- 各機器は frpc で VPS に常時アウトバウンド接続するだけでよい。

概要構成
- VPS: Sakura VPS (Global IP: 133.167.107.172)
- DNS: Cloudflare が権威DNS（お名前.comのNSは Cloudflare に委任）
- エッジ: Caddy (HTTP only, :80)
- 中継: frps (control :7000 TLS-only, vhostHTTP :8080)
- クライアント: 各機器の frpc（protocol=wss, type=http, subdomain=各機器ID）

DNS 状態（Cloudflare）
- A @ → 133.167.107.172（DNS only/灰色）
- A * → 133.167.107.172（DNS only/灰色）
- A www → 133.167.107.172（DNS only/灰色）
- A influx → 133.167.107.172（DNS only/灰色）
- 注意: ゾーン内 apex(NS) に dnsv.jp への NS レコードが残ると権威分裂の原因。存在する場合は削除する。

ネットワーク/ポート（VPS）
- UFW 開放: 22, 80, 443, 7000, 8080（Terraform で投入）
- 実サービス待受:
  - 80/tcp: Caddy（HTTPのみ, auto_https off）
  - 8080/tcp: frps vhost HTTP（Caddy → frps）
  - 7000/tcp: frps 制御接続（TLS必須; frpcのwssで接続）
  - 443/tcp: Caddy コンテナで公開はあるが HTTP only 構成では未使用（閉じてもよい）

コンテナ（docker-compose）
- frps: ghcr.io/fatedier/frps:v0.61.0
  - command: ["--tls-only", "-c", "/etc/frp/frps.toml"]（Terraform変数 tls_force=true のとき）
  - ports: 7000/tcp, 8080/tcp 公開
  - volume: /etc/frp/frps.toml（テンプレから生成）
- caddy: slothcroissant/caddy-cloudflaredns:latest
  - ports: 80, 443 公開（HTTP only 構成では 80 のみ利用）
  - volume: /etc/caddy/Caddyfile（テンプレから生成）
- influxdb: influxdb:2.7
  - ports: 8086/tcp（ホスト未公開。Caddy経由のみ）
  - volumes: /var/lib/influxdb2（docker volume: influxdb_data）
  - 初期化: DOCKER_INFLUXDB_INIT_*（ユーザー/ORG/BUCKET/token/retention）

Caddy 設定（HTTP only の要点）
- global: auto_https off
- site: `http://kimulabfrp.jp` → respond 200（ヘルス/案内）
- site: `http://*.kimulabfrp.jp` → reverse_proxy frps:8080
- site: `https://influx.${domain}` → TLS(dns-01) で終端し reverse_proxy influxdb:8086
- 参考: 将来 https 運用は `dns01-cloudflare` モードに切替可（ワイルドカード証明書）

frps 設定
- /etc/frp/frps.toml（テンプレから生成）
  - bindPort = 7000
  - vhostHTTPPort = 8080
  - subdomainHost = "kimulabfrp.jp"
  - [auth] token = (tfvarsの値)
  - [webServer] 0.0.0.0:7500（ダッシュボード; 外部公開なし）
- TLS: 設定ファイルでは指定しない。コンテナ引数 `--tls-only` で強制（v0.61.0実装に整合）

Terraform/テンプレート
- templates/Caddyfile.tmpl（HTTP only / else で dns01-cloudflare）
- templates/frps.toml.tmpl（bind/vhostHTTP/subdomainHost/auth/webServer）
- templates/docker-compose.yml.tmpl（frpsに --tls-only を条件付与, Caddy を有効化）
- main.tf: null_resource + file/remote-exec で配置/起動、UFW開放。
- variables.tf: domain, frp_token, tls_force, caddy_mode など

確認済みの挙動
- ルート: Host=kimulabfrp.jp で 200（Caddy respond）
- 未割当サブドメイン: 404（正常）
- frps: `--tls-only` で起動、7000/8080 待受
- ログ: 旧 "unknown field enable" は解消済（TLS設定はCLIフラグ化）

運用ツール
- `scripts/check_frp_stack.sh`（疎通/設定/HTTPヘルスの統合チェック）
- `scripts/install_frpc_ubuntu.sh`（Ubuntu機器への frpc 導入 + systemd 常駐）
- ドキュメント: `docs/frp_dns_study_guide.md`, `docs/2025-11-09_frp_log.md`

既知の注意点/改善余地
- Cloudflare ゾーン内 apex の NS（dnsv.jp）が残ると権威分裂 → 削除推奨
- 443公開は現状未使用 → セキュリティポリシーに応じて閉じる/利用方針を決める
- frps ダッシュボード(7500)は非公開 → 必要時は SSH トンネルで閲覧

次の拡張予定（別途要件化）
- InfluxDB のバックアップ自動化（cron/スクリプト）
- 監視（/health、ディスク残量、コンテナ状態）
