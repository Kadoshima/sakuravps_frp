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
