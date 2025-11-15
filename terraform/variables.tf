variable "vps_ip" {
  type        = string
  description = "Sakura VPS の グローバルIP"
}

variable "ssh_user" {
  type        = string
  default     = "ubuntu" # 例: Ubuntuイメージなら ubuntu / Debianなら debian / Almaなら root など
  description = "SSH接続ユーザー名"
}

variable "private_key_path" {
  type        = string
  description = "SSH秘密鍵のパス (ローカル)"
  sensitive   = true
}

variable "bastion_host" {
  type        = string
  default     = ""
  description = "踏み台を使うなら指定（不要なら空のまま）"
}

variable "bastion_user" {
  type        = string
  default     = ""
  description = "踏み台のユーザー名"
}

variable "domain" {
  type        = string
  description = "サブドメイン親FQDN（例: proxy.example.com）。*.proxy.example.comをVPSへ向ける"
}

variable "acme_email" {
  type        = string
  description = "Caddyの証明書通知先メールアドレス（Let's Encrypt用）"
}

variable "frp_token" {
  type        = string
  description = "frpsとfrpc間の認証トークン（長い乱数を推奨）"
  sensitive   = true
}

variable "open_ports" {
  type        = list(string)
  default     = ["22", "80", "443", "7000", "8080"]
  description = "UFWで開放するポート番号のリスト"
}

variable "cloudflare_token" {
  type        = string
  description = "CloudflareのAPIトークン（DNS-01チャレンジ用）"
  sensitive   = true
}

variable "tls_enable" {
  type        = bool
  default     = true
  description = "frps: TLS を有効化するか"
}

variable "tls_force" {
  type        = bool
  default     = true
  description = "frps: TLS を強制するか（true 推奨）"
}

variable "enable_caddy" {
  type        = bool
  default     = true
  description = "Caddy を起動するか（false で frps のみ）"
}

variable "caddy_mode" {
  type        = string
  default     = "http-only" # "dns01-cloudflare" に切替可
  description = "Caddy の動作モード: http-only | dns01-cloudflare"
}

variable "force_redeploy" {
  type        = bool
  default     = false
  description = "true にすると次の apply で必ず再配備して実体を上書きする"
}

# InfluxDB (optional)
variable "enable_influxdb" {
  type        = bool
  default     = false
  description = "InfluxDB をデプロイするか"
}

variable "influxdb_init_username" {
  type        = string
  description = "InfluxDB 初期ユーザー名"
  sensitive   = true
}

variable "influxdb_init_password" {
  type        = string
  description = "InfluxDB 初期パスワード"
  sensitive   = true
}

variable "influxdb_init_org" {
  type        = string
  default     = "kimulab"
  description = "InfluxDB ORG 名"
}

variable "influxdb_init_bucket" {
  type        = string
  default     = "IoT"
  description = "InfluxDB 初期バケット名"
}

variable "influxdb_init_admin_token" {
  type        = string
  description = "InfluxDB 管理トークン (十分に長いランダム文字列)"
  sensitive   = true
}

variable "influxdb_retention" {
  type        = string
  default     = "90d"
  description = "InfluxDB バケットのリテンション期間 (例: 90d)"
}
