# Sakura VPS FRP Proxy Setup

Sakura VPS上にfrps（Fast Reverse Proxy Server）とCaddy（自動TLS）を**Terraformだけで**セットアップし、複数のクライアントへのリバースプロキシ環境を構築します。

## 特徴

- **Terraform一発デプロイ** - `terraform apply` だけで完全に構築完了
- **自動HTTPS** - Caddyが Let's Encrypt で証明書を自動取得
- **サブドメインルーティング** - `*.proxy.example.com` でクライアントごとにアクセス
- **安全な通信** - WSS (WebSocket Secure) でクライアント接続

## アーキテクチャ

```
Internet (HTTPS)
    ↓
Caddy (443) - 自動TLS終端
    ↓
frps (8080) - HTTPリバースプロキシ
    ↓
frpc クライアント (WSS, 7000)
```

**主要コンポーネント:**
- **Terraform**: インフラストラクチャのプロビジョニング
- **Docker + Compose**: frps/Caddyのコンテナ管理
- **Caddy**: 自動HTTPS証明書とリバースプロキシ
- **frps**: サブドメイン単位のルーティング

## 前提条件

### 1. DNS設定
以下のDNSレコードを設定してください：

```
proxy.example.com    A     <VPS_IP>
*.proxy.example.com  A     <VPS_IP>
```

### 2. ローカル環境
- Terraform >= 1.6.0
- SSH鍵認証の設定

## クイックスタート

### Step 1: 設定ファイルの準備

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` を編集：

```hcl
vps_ip           = "133.167.107.172"       # あなたのVPS IP
ssh_user         = "ubuntu"                # SSHユーザー
private_key_path = "~/.ssh/id_ed25519"    # SSH秘密鍵

domain     = "proxy.example.com"           # あなたのドメイン
acme_email = "you@example.com"             # Let's Encrypt通知用
frp_token  = "your-long-random-token-here" # 長い乱数（32文字以上推奨）
```

### Step 2: デプロイ

```bash
terraform init
terraform apply
```

完了！これだけで以下が自動的に：
- ✓ Docker/Docker Composeインストール
- ✓ UFWファイアウォール設定
- ✓ frps + Caddy コンテナ起動
- ✓ HTTPS証明書自動取得

### Step 3: 動作確認

```bash
# VPSでコンテナ確認
ssh ubuntu@<VPS_IP>
docker ps

# 出力例:
# CONTAINER ID   IMAGE                  PORTS
# abc123...      caddy:2                0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
# def456...      fatedier/frps:latest   0.0.0.0:7000->7000/tcp, 0.0.0.0:8080->8080/tcp
```

ブラウザで `https://proxy.example.com` にアクセスして、HTTPSで接続できることを確認。

## クライアント設定

### frpcのインストール

各クライアント（PC、Raspberry Pi等）に [frp](https://github.com/fatedier/frp/releases) をインストール。

### frpc.toml 設定例

```toml
serverAddr = "proxy.example.com"
serverPort = 7000
protocol   = "wss"

[auth]
method = "token"
token  = "your-long-random-token-here"  # サーバーと同じトークン

[[proxies]]
name      = "mypc-web"
type      = "http"
localPort = 8080
subdomain = "mypc"  # => https://mypc.proxy.example.com でアクセス可能

# Basic認証（オプション）
httpUser     = "admin"
httpPassword = "secret"
```

### frpc起動

```bash
frpc -c frpc.toml
```

これで `https://mypc.proxy.example.com` からローカルの8080番ポートにアクセスできます。

## ディレクトリ構造

```
sakuravps_frp/
├── terraform/              # メイン構成
│   ├── main.tf            # プロビジョニングロジック
│   ├── variables.tf       # 変数定義
│   ├── outputs.tf         # 出力定義
│   ├── terraform.tfvars.example
│   ├── templates/         # 設定テンプレート
│   │   ├── Caddyfile.tmpl
│   │   ├── frps.toml.tmpl
│   │   └── docker-compose.yml.tmpl
│   └── CLAUDE.md          # 詳細ドキュメント
├── ansible/               # (レガシー・未使用)
└── README.md              # このファイル
```

## 設定の更新

設定を変更したい場合：

1. `terraform.tfvars` または `templates/*.tmpl` を編集
2. `terraform apply` を実行

Terraformが変更を検出して自動的に再デプロイします。

## トラブルシューティング

### Caddyが証明書を取得できない

**原因:**
- DNSレコードが正しく設定されていない
- ポート80/443が開いていない

**対処:**
```bash
# DNS確認
dig proxy.example.com
dig mypc.proxy.example.com

# ファイアウォール確認
ssh ubuntu@<VPS_IP> "sudo ufw status"

# Caddyログ確認
ssh ubuntu@<VPS_IP> "docker logs caddy"
```

### frpcが接続できない

**原因:**
- トークンが一致していない
- ポート7000が閉じている

**対処:**
```bash
# frpsログ確認
ssh ubuntu@<VPS_IP> "docker logs frps"

# トークンの確認（terraform.tfvarsとfrpc.tomlを比較）

# ポート確認
ssh ubuntu@<VPS_IP> "sudo ufw status | grep 7000"
```

### コンテナが起動しない

```bash
# VPSにSSHして確認
ssh ubuntu@<VPS_IP>
cd /opt/proxy/compose

# ログ確認
sudo docker compose logs

# 再起動
sudo docker compose restart

# 完全に再構築
sudo docker compose down
sudo docker compose up -d
```

### 設定を完全にリセット

```bash
# ローカル
terraform destroy

# VPS上
ssh ubuntu@<VPS_IP>
cd /opt/proxy/compose
sudo docker compose down -v
sudo rm -rf /opt/proxy
```

## 運用のベストプラクティス

### セキュリティ

1. **強力なトークン**: `frp_token` は32文字以上のランダム文字列
   ```bash
   # 生成例
   openssl rand -base64 32
   ```

2. **Git管理**: `terraform.tfvars` は `.gitignore` に追加
   ```bash
   echo "terraform/terraform.tfvars" >> .gitignore
   echo "terraform/*.tfstate*" >> .gitignore
   echo "terraform/.terraform/" >> .gitignore
   ```

3. **Basic認証**: 公開したくないサービスは frpc側で `httpUser`/`httpPassword` を設定

### モニタリング

```bash
# コンテナ状態を定期確認
ssh ubuntu@<VPS_IP> "docker ps"

# ログ監視
ssh ubuntu@<VPS_IP> "docker logs -f caddy"
ssh ubuntu@<VPS_IP> "docker logs -f frps"
```

### バックアップ

重要な設定ファイル：
- `terraform/terraform.tfvars` (ローカル)
- `/opt/proxy/config/*` (VPS)

```bash
# VPSの設定をバックアップ
ssh ubuntu@<VPS_IP> "sudo tar czf /tmp/proxy-config-backup.tar.gz /opt/proxy/config"
scp ubuntu@<VPS_IP>:/tmp/proxy-config-backup.tar.gz ./backups/
```

## 今後の拡張

- [ ] **DNS自動化**: Terraform CloudFlare/Sakura DNS providerでDNSも管理
- [ ] **SOPS暗号化**: 秘密情報をGit安全に管理
- [ ] **モニタリング**: Prometheus + Grafana 追加
- [ ] **複数VPS**: Terraform workspaceで複数環境管理
- [ ] **自動バックアップ**: cron + rsync でconfig自動バックアップ

## 技術詳細

詳細なアーキテクチャ、トラブルシューティング、開発ノートは以下を参照：

- **[terraform/CLAUDE.md](terraform/CLAUDE.md)** - 包括的な技術ドキュメント

## 参考リンク

- [frp Documentation](https://github.com/fatedier/frp)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## ライセンス

このプロジェクトは個人利用を想定しています。各コンポーネント（frp, Caddy, Terraform, Docker）は各自のライセンスに従います。

## 貢献

バグ報告や改善提案は Issue でお願いします。
