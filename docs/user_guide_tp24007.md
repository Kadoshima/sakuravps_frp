# 利用者向けガイド（ユーザー: tp24007）

対象
- ユーザーID: `tp24007`
- 目的: 公開サービスの閲覧/利用、および InfluxDB でのデータ閲覧・書き込み

提供中エンドポイント
- FRP中継（HTTP/WS）: `http://<機器ID>.kimulabfrp.jp`
  - 例: `http://test.kimulabfrp.jp`
  - WebSocketも同URLで利用可能（アプリがWS対応の場合）
- InfluxDB（TLS）: `https://influx.kimulabfrp.jp`
  - ヘルス: `https://influx.kimulabfrp.jp/health`（200で正常）

注意
- パスワード/トークンは管理者から配布されます。本ドキュメントには記載しません。
- 共有端末/ノートPCからの認証情報の保管に注意してください。

---

## 1. InfluxDB の使い方（tp24007）

1) ログイン
- ブラウザで `https://influx.kimulabfrp.jp` を開く
- ユーザー: `tp24007`
- パスワード: 管理者配布のもの
- ORG: `kimulab`
- 既定バケット: `IoT`（リテンション 90日）

2) トークン作成（推奨）
- UI上部メニュー → Load Data → API Tokens
- 目的に応じて Token を発行
  - 全権限が不要なら、Read/Write の最小権限で発行
- 表示された Token は再表示できないため、必ず安全な場所に保管

3) 書き込み（Line Protocol）
- エンドポイント（Write API）:
  - `POST https://influx.kimulabfrp.jp/api/v2/write?org=kimulab&bucket=IoT&precision=ns`
- ヘッダ: `Authorization: Token <YOUR_TOKEN>`
- 例（curl）
```bash
now=$(date +%s%N)
curl -sS -XPOST \
  "https://influx.kimulabfrp.jp/api/v2/write?org=kimulab&bucket=IoT&precision=ns" \
  -H "Authorization: Token <YOUR_TOKEN>" \
  --data-raw "ping value=1 ${now}"
```

4) クエリ（Flux）
- エンドポイント（Query API）:
  - `POST https://influx.kimulabfrp.jp/api/v2/query`
- ヘッダ: `Authorization: Token <YOUR_TOKEN>`, `Content-Type: application/vnd.flux`
- 例（直近5分・1件）
```bash
curl -sS \
  -H "Authorization: Token <YOUR_TOKEN>" \
  -H "Content-Type: application/vnd.flux" \
  -d 'from(bucket:"IoT") |> range(start: -5m) |> limit(n:1)' \
  https://influx.kimulabfrp.jp/api/v2/query
```

5) 典型トラブル
- 401/403: Token不正・権限不足 → Tokenの権限/文字列を確認
- 404/5xx: エンドポイントURL/パラメータ誤り、混雑 → 数分後に再実行
- 書き込み成功だが見えない: 時刻（precision=ns）が未来/過去になっていないか確認

---

## 2. 公開サービス（FRP）の使い方

- 公開URL: `http://<機器ID>.kimulabfrp.jp`
  - 例: `http://test.kimulabfrp.jp`
- 404 が返る場合は、機器側の frpc が未接続、またはローカルアプリが停止中の可能性があります。担当者へ連絡してください。
- WebSocket は同URLで透過します（アプリがWS対応であること）。

機器を新規に公開したいとき
- 管理者へ以下を申請
  - 希望の機器ID（サブドメイン）
  - 機器のローカルポート
  - 必要な公開範囲/制限（あれば）
- セットアップは以下ガイドを参照
  - `docs/end_user_guide.md`（frpc セットアップ／Ubuntuスクリプトあり）

---

## 3. セキュリティと運用の注意

- 認証情報（パスワード/トークン）は第三者と共有しない
- 端末のウイルス対策・OSアップデートを最新に保つ
- 利用が終わったら UI からログアウト
- 異常時は管理者へ以下を連絡
  - 該当URL、時刻、実行した操作（例: 書き込み/クエリ/閲覧）
  - エラーメッセージ（HTTPコード/メッセージ）

---

## 4. 問い合わせ先
- 運用担当（管理者）までご連絡ください
  - 申請・障害・権限追加など
  - 伝える情報: ユーザーID (`tp24007`)、目的、希望内容

以上
