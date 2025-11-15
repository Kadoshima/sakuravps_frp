# 新規ユーザー受け入れ手順（管理者用）

目的
- 新しい利用者（デバイス）に対して、サブドメインを割り当て、FRP経路で安全に公開できるようにする。
- 入口は Caddy で TLS 終端（DNS-01 / Cloudflare）。FRP の vhostHTTP(8080) に中継。

前提（本環境は満たしている）
- DNS（Cloudflare）
  - `A @` / `A *` / `A influx` → VPS IP（DNS only/灰色雲）
  - Cloudflare API トークン: Zone.DNS(Edit) + Zone.Zone(Read), zone=kimulabfrp.jp
- Caddy（TLS）
  - ワイルドカード: `https://*.kimulabfrp.jp`（DNS-01/Cloudflare）
- FRP（サーバ）
  - frps: 7000/tcp（--tls-only）、vhostHTTPPort=8080、subdomainHost="kimulabfrp.jp"

手順
1) デバイスID（サブドメイン）の割当
- 命名例: 半角英数・ハイフン（例: pc001-web）
- 既存との重複を避ける（台帳または docs/ にリスト化を推奨）
- 例: `pc001-web.kimulabfrp.jp`

2) ワイルドカードTLSの確認（初回取得）
- VPSでSNI指定のHTTPSを叩いて、証明書の自動取得を誘発
  - `ssh ubuntu@133.167.107.172 "curl -Ik --resolve <id>.kimulabfrp.jp:443:127.0.0.1 https://<id>.kimulabfrp.jp"`
  - 初回はACME取得ログ（caddy）に `challenge/obtain/certificate obtained` が出る
  - frpc未接続なら 404 で正常

3) 利用者へ伝達する情報
- デバイスID（サブドメイン）: 例 `pc001-web`
- FRP接続先（共通）
  - serverAddr=`kimulabfrp.jp`
  - serverPort=`7000`
  - 認証 token=`<FRP_TOKEN>`（tfvarsの値）
- 利用者向けガイド: `docs/new_user_user.md` / `docs/user_guide_tp24007.md`

4) 接続後の確認（サーバ側）
- frpsログでログイン/公開開始を確認
  - `ssh ubuntu@133.167.107.172 "docker logs frps --since 5m | egrep -i 'client login|start proxy|http proxy listen' -n || true"`
  - 例: `[pc001-web] http proxy listen for host [pc001-web.kimulabfrp.jp]`
- 経路確認（VPSから）
  - `ssh ... "curl -Ik --resolve <id>.kimulabfrp.jp:443:127.0.0.1 https://<id>.kimulabfrp.jp"`

5) 代表的なトラブルと対処
- 404（アクセス時）
  - frpc未接続 / subdomain不一致 / 利用者ローカルサービス未起動
  - frpsログの `http proxy listen for host [...]` を確認
- TLS handshake error（no certificate available）
  - 初回取得が未実行 → Caddy再起動 or 上記SNI付きcurlで取得を誘発
  - Cloudflareトークン権限不足 → Zone.DNS(Edit) / Zone.Read を確認
- unexpected EOF（frpc）
  - frpsは--tls-only（生TLS）。frpcは `protocol=tcp` + `[transport].tls.enable=true`
  - 7000到達性: `nc -vz kimulabfrp.jp 7000`

運用ヒント
- 割当台帳を整備（ID / 所有者 / 目的 / 作成日）
- 高頻度アクセス先はCaddyでアクセス制御やレート制限も検討可
- FRPトークンは全体共通。将来は分離運用（ACL/プラグイン）も検討余地あり

参照
- Caddyfile: `/opt/proxy/config/Caddyfile`
- frps.toml: `/opt/proxy/config/frps.toml`
- docker-compose: `/opt/proxy/compose/docker-compose.yml`
