# InfluxDB 要件定義（ドラフト）

作成日: 2025-11-09
スコープ: 既存の Sakura VPS（FRP/Caddy 稼働中）に InfluxDB 2.x を追加する。

## 1. 目的/ユースケース
- 時系列データ（メトリクス/イベント）を保存・参照する API/UI を提供する。
- 今後の可視化や外部連携に備え、HTTPS で安全に外部公開可能な構成にする。

## 2. 推奨アーキテクチャ（方針）
- 同一VPS上の別コンテナとして `influxdb:2.x` を追加。
- 8086 はホストへ公開せず、Docker 内ネットワークのみで LISTEN。
- Caddy で `influx.${domain}` を TLS 終端し、`influxdb:8086` に reverse_proxy。
- 永続化は Docker volume（例: `influxdb_data`）。
- 初期セットアップ（ユーザー/ORG/BUCKET/token）は環境変数で自動化。

## 3. 機能要件（Functional）
- バージョン: InfluxDB 2.7系（2.x 安定）
- エンドポイント:
  - UI: https://influx.${domain}
  - Health: `GET /health` → 204
  - Write API: `POST /api/v2/write?org=...&bucket=...&precision=ns`
  - Query API: `POST /api/v2/query`（Flux）
- 認証: Token 認証（admin token + app token）

## 4. 非機能要件（NFR）
- 可用性: 単一VPS内でのコンテナ運用（SLAはVPSに準ずる）
- 性能（想定入力）: 10分あたり約22.2KB → 約3.2MB/日（Piezo/Solar/Capacitor/ヘッダー合算）
- 容量見積: 3.2MB/日 × 30日 ≒ 96MB/月、× 90日 ≒ 288MB（メタ/インデックスを見込み 1.2倍で ≒ 350MB）
- リテンション: 既定 90d（90日）
- バックアップ: 毎日 02:30 JST に取得、保持 30日、保存先（ローカル）`/opt/influx/backups`
- 監視: Healthチェック/ディスク残量/コンテナ状態（`docker ps`）

## 5. セキュリティ
- 公開は `influx.${domain}` のみ（Caddy: TLS）。Cloudflare は DNS only（灰色）
- 管理UI/APIは必ず HTTPS 経由、Token は機密管理（tfvars/Secrets）
- 必要なら IP 制限（Caddyの `remote_ip`/`client_ip` マッチで制御）

## 6. DNS/証明書
- DNS: Cloudflare に `A influx → VPS IP`（DNS only, TTL Auto）
- 証明書: Caddy `dns01-cloudflare` モードで取得（既存 Cloudflare API Token を使用）

## 7. デプロイ方式（Terraform/Compose 変更）
- variables.tf（追加）
  - `enable_influxdb` (bool, default=false)
  - `influxdb_init_username` (sensitive)
  - `influxdb_init_password` (sensitive)
  - `influxdb_init_org`
  - `influxdb_init_bucket`
  - `influxdb_init_admin_token` (sensitive)
- templates/docker-compose.yml.tmpl（追加）
  - サービス `influxdb`:
    - image: influxdb:2.7
    - volumes: `influxdb_data:/var/lib/influxdb2`
    - environment: DOCKER_INFLUXDB_INIT_*（上記）
    - ports: 公開なし（Caddy経由のみ）
  - volumes: `influxdb_data:` 追加
- templates/Caddyfile.tmpl（追加）
  - `influx.${domain} { tls { dns cloudflare } reverse_proxy influxdb:8086 }`（dns01-cloudflare モード時）
- main.tf: 既存の file 配置/compose up により自動反映

## 8. 受け入れ基準（Acceptance Criteria）
- `https://influx.${domain}` にアクセスし、UI が開く（ブラウザの証明書OK）
- `curl -I https://influx.${domain}/health` → 204
- 初期ユーザーでログイン可、指定ORG/BUCKETが存在
- Write/Query API が Token 認証で動作
- バックアップがスケジュール通りに取得・保管される

## 9. オペレーション
- バックアップ: `influx backup /backups/$(date +%F)` を cron 化（ホスト/コンテナいずれか）
- 復元: `influx restore` 手順を別紙整備
- アップグレード: コンテナイメージのタグ更新 → apply（事前にバックアップ必須）

## 10. 決めるべき項目（確定）
- サブドメイン名: influx.${domain}（例: influx.kimulabfrp.jp）
- リテンション期間: 90d
- 想定投入レート/容量: 約3.2MB/日（≒ 96MB/月, 90日で≒ 288MB, 安全係数込み≒ 350MB）
- バックアップ: 毎日 02:30 JST, 保存先=ローカル `/opt/influx/backups`, 保持=30日
- 初期セットアップ値:
  - ユーザー名: tp24007（推奨: 変更/強化）
  - パスワード: tp24007（要強化。本番は12+桁のランダムを推奨）
  - ORG: kimulab（組織/テナント名の概念。バケットやトークンを束ねる単位）
  - BUCKET: IoT（retention=90d）
  - ADMIN TOKEN: 後述の生成手順で作成（64+文字のランダム）
- 公開範囲制限: 全許可（必要に応じて将来IP制限を追加可）

補足: ORG とは？
- InfluxDB 2.x における“組織”の概念で、ダッシュボード/バケット/トークン/ユーザーをまとめる“作業スペース”。今回の用途では `kimulab` を指定。

管理トークン（ADMIN TOKEN）の作り方（例）
```
python3 - <<'PY'
import secrets,string
alphabet=string.ascii_letters+string.digits
print(''.join(secrets.choice(alphabet) for _ in range(64)))
PY
```
この値を `terraform/tftest.tfvars` の `influxdb_init_admin_token` に設定（リポジトリ外で管理推奨）。

## 11. 今後の進め方
1) 本ドキュメントの [要回答] を確定
2) ドキュメント更新（確定値反映）
3) Terraform/テンプレート改修（最小差分）
4) `terraform apply` で反映
5) 検証（Acceptance Criteria）
6) 運用に移行（バックアップ/監視）
