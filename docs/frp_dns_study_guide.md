# FRP と DNS の基礎からわかる中継構成ガイド

このドキュメントは、今回遭遇した「Cloudflare とお名前.com の設定が混在して DNS が期待どおり反映されない」問題を題材に、大学2年生レベルでも理解できるように、基礎から応用まで順に学べるよう構成しています。最初に全体像を掴んでから、段階的に細部へ進みます。

---

## 1. 5分で全体像（今回やりたいこと）

- 目的
  - Sakura VPS を“中継点”にして、インターネットからの HTTP/WS を、社内/宅内機器へ転送したい。
  - 機器側は外向きに常時接続（アウトバウンド）だけでOK。外からの穴開けは不要。
- 主な登場人物
  - Caddy（VPSの80番を受けるフロント）: Host名（サブドメイン）でリクエストをふりわけ。
  - frps（FRPサーバ、VPS上）: サブドメインごとのルートを管理し、frpcへ橋渡し。
  - frpc（各機器上のエージェント）: VPSへアウトバウンド接続を張り続け、ローカルサービスへ転送。
  - Cloudflare（権威DNS）: `@` と `*` のAレコードで “Caddyの入口” に到達させる。
- 流れ（HTTPの例）
  1. ブラウザ → `http://device1.kimulabfrp.jp` にアクセス
  2. CloudflareのDNS → VPSのIPを返す
  3. Caddy(80) → Host: device1.kimulabfrp.jp を見て frps:8080 へ中継
  4. frps → サブドメイン `device1` に紐づく frpc へ転送
  5. frpc → 機器の `localhost:8080` へ届ける

---

## 2. DNS の基礎（なぜ“権威DNS”が大事？）

- DNS は「名前 → IP」を返すための“電話帳”。
- 役割の違い
  - リカーシブDNS（キャッシュDNS）: 端末やISP/公共DNS（1.1.1.1、8.8.8.8 等）。答えを“取りに行く”人。
  - 権威DNS: そのドメインの“公式の答え”を持つサーバ（今回: Cloudflare）。
- 委任（デリゲーション）
  - ルート → `.jp` → `kimulabfrp.jp` という鎖で、「どのサーバが正しい答えを持っているか」を順に“紹介”していく。
  - レジストラ（お名前.com）で“ネームサーバー（NS）”を Cloudflare の `brady.ns.cloudflare.com / margaret.ns.cloudflare.com` に設定すると、「kimulabfrp.jp の正しい答えは Cloudflare にある」と世界に告げることになる。
- レコードの種類（よく使う）
  - `A`（IPv4） / `AAAA`（IPv6）: 名前 → IP
  - `CNAME`: 別名（apexでは注意、Cloudflareは“CNAMEフラッテン”を持つ）
  - `NS`: 委任に使う（サブゾーンの委任など）。apexに“別の権威”を書くと混乱の元
  - `TXT`: SPF/DKIMなどテキスト情報
- TTL とキャッシュ
  - 返事はしばらく“覚えられる”。修正後すぐに反映しないのはTTLやキャッシュが理由。
  - `dig +trace` で、誰がどうやって答えを集めたかを辿れる。

---

## 3. 事例研究：なぜ Cloudflare の変更が効かず、お名前.comの変更が効いた？

- 症状
  - Cloudflare で `@` と `*` の A レコードを `133.167.107.172` にしても、反映されない。
  - お名前.com 側のDNSレコードを直したら、すぐ効いた。
- 原因（権威の分裂）
  - Cloudflare ゾーン内に、apex に対して `NS 01〜04.dnsv.jp`（お名前.com）なレコードが存在していた。
  - これは Cloudflare の“自動インポート”等で紛れ込むことがある。
  - 結果、解決系によっては「お名前.com 側を権威とみなす」経路に流れ、Cloudflare の変更が無視された。
- 正しい直し方
  1. Cloudflare のゾーンから、apex の `NS kimulabfrp.jp -> *.dnsv.jp` を“すべて削除”。
  2. Cloudflare ゾーンには、`A @` と `A *`（必要なら `A www`）だけ残す（いずれも DNS only/灰色雲）。
  3. レジストラ（お名前.com）の“ネームサーバー設定”は Cloudflare の `brady/margaret` のまま。
- 確認コマンド（例）
  - 権威の鎖: `dig +trace kimulabfrp.jp`
  - 伝播確認: `dig +short @1.1.1.1 test.kimulabfrp.jp` / `@8.8.8.8`

---

## 4. FRP の基礎（frps と frpc）

- 役割
  - frps（サーバ）: VPS上。`7000/TCP` で frpc からの常時接続を受ける。`vhostHTTPPort=8080` でサブドメイン多重化。
  - frpc（クライアント）: 各機器上。VPSへアウトバウンドで常時接続し、ローカルサービスへ転送。
- なぜ“サブドメイン”が効く？
  - frps の vhostHTTP は、Hostヘッダ（= サブドメイン）でどの frpc に届けるかを決められるから。
- プロトコルとTLS
  - 今回はサーバ側を `--tls-only`（7000はTLS必須）に設定。
  - frpc は `protocol = "wss"` を使うと、企業ネットワーク越しでも通りやすい。
- frpc 設定例（機器のローカルHTTPが8080）
  ```toml
  serverAddr = "kimulabfrp.jp"
  serverPort = 7000
  protocol   = "wss"

  [auth]
  method = "token"
  token  = "<Terraformで設定したトークン>"

  [[proxies]]
  name      = "device1"
  type      = "http"
  localPort = 8080
  subdomain = "device1"  # → http://device1.kimulabfrp.jp
  ```

---

## 5. エッジ（Caddy）の役割

- 今回は“HTTPのみ”で運用（80番）。
  - ルート（apex）は `respond 200`（ヘルスチェック/案内）
  - サブドメインは `reverse_proxy frps:8080`
- Cloudflare 側は“DNS only（灰色雲）”。
  - Proxy（オレンジ雲）や “Always Use HTTPS” はオフ。
  - もしエッジでHTTPSが必要になったら、Caddyを `dns01-cloudflare` モードに切替。

---

## 6. 検証ハンドブック（順番に試す）

1) DNS
- `dig +short kimulabfrp.jp` → VPSのIP
- `dig +short test.kimulabfrp.jp` → VPSのIP（`*` が効いている）

2) Caddy
- VPSローカルで
  - `curl -I -H 'Host: kimulabfrp.jp' http://127.0.0.1/` → 200
  - `SUB=check$RANDOM; curl -I -H "Host: $SUB.kimulabfrp.jp" http://127.0.0.1/` → frpc未接続なら404

3) frps
- ポート: `ss -ltnp | grep ':7000 '`（LISTEN を確認）
- ログ: `docker logs frps --since 5m | grep -i 'client login'`

4) frpc
- 起動: `./frpc -c frpc.toml`
- systemd化（Linux）: `ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml` / `Restart=always`

5) 終端～機器まで
- `curl -I http://device1.kimulabfrp.jp` → 200（frpc接続中）
- WebSocket（任意）: `wscat -c ws://device1.kimulabfrp.jp/path`

---

## 7. よくある落とし穴

- Cloudflare のゾーンに“apexの NS（他社）”が残っている → 権威分裂
- Cloudflare の“オレンジ雲（Proxy）”のまま → 期待しないリダイレクト/ヘッダ/証明書終端
- ワイルドカード `*` が効かない → 明示レコード（例: `www`）が優先
- CNAME を apex に置く → プロバイダ次第。Cloudflareは“フラッテン”があるが、まずは `A` を使うのが無難
- TTL とキャッシュで“直したのに変わらない” → `dig +trace` で経路確認
- 企業ネットワークで TCP 7000 が塞がれる → `protocol=wss` で回避可能

---

## 8. 運用チェックリスト（短い版）

- DNS（Cloudflare）
  - [ ] `A @` / `A *` は VPS IP、DNS only（灰色）
  - [ ] ゾーン内 apex の NS に `*.dnsv.jp` が無い
  - [ ] （必要なら）`A www` も設定
- Caddy（VPS）
  - [ ] 80番でLISTEN、apexは200、`*.domain`は frps:8080 へ
- frps
  - [ ] `--tls-only` で 7000/TCP 待受
  - [ ] ログに `client login` が出る
- frpc（各機器）
  - [ ] `protocol=wss`、token一致、`type=http`、`subdomain` 付与
  - [ ] systemd で常駐化

---

## 9. 用語ミニ辞典

- 権威DNS（authoritative DNS）: そのゾーンの“正解”を持つサーバ
- 委任（delegation）: 親が「この子の正解はこのNSに聞いて」と紹介すること
- リカーシブDNS: クライアントの代わりに答えを探してくれるキャッシュDNS
- TTL: 答えの“賞味期限”。短いほど反映は早いが負荷は増える
- apex: ゾーンの“根っこ”（`kimulabfrp.jp` のこと）
- ワイルドカード: `*.` で始まる、未定義のサブドメインをまとめて扱う記法

---

## 10. 付録（スニペット）

- Caddy（HTTP only の要点）
  ```caddyfile
  {
    auto_https off
  }
  http://kimulabfrp.jp {
    respond "FRP edge is running (HTTP-only)." 200
  }
  http://*.kimulabfrp.jp {
    reverse_proxy frps:8080
  }
  ```

- frpc（最小例）
  ```toml
  serverAddr = "kimulabfrp.jp"
  serverPort = 7000
  protocol   = "wss"
  [auth]
  method = "token"
  token  = "<長い乱数>"
  [[proxies]]
  name      = "device1"
  type      = "http"
  localPort = 8080
  subdomain = "device1"
  ```

- 代表的な確認コマンド
  ```bash
  # 権威の経路
  dig +trace kimulabfrp.jp
  # 伝播とキャッシュ
  dig +short @1.1.1.1 test.kimulabfrp.jp
  dig +short @8.8.8.8 test.kimulabfrp.jp
  # Caddyローカルの挙動
  curl -I -H 'Host: kimulabfrp.jp' http://127.0.0.1/
  SUB=check$RANDOM; curl -I -H "Host: $SUB.kimulabfrp.jp" http://127.0.0.1/
  ```

---

以上。さらに詳しい図解やクイズ形式の追補が必要なら、このガイドに追記します。
