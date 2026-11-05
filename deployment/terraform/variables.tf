variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "domain" {
  type    = string
  default = "stevekc.com"
}

variable "bucket_name" {
  type    = string
  default = "stevekc-uploads"
}

variable "web_bucket_name" {
  type    = string
  default = "stevekc.com"
}

variable "role_name" {
  type    = string
  default = "stevekc-upload-lambda-role"
}

variable "policy_name" {
  type    = string
  default = "stevekc-upload-lambda-policy"
}

variable "table_name" {
  type    = string
  default = "stevekc-file-inbox"
}

variable "pool_name" {
  type    = string
  default = "stevekc-users"
}

variable "admin_email" {
  type = string
}

variable "admin_email_password" {
  type      = string
  sensitive = true
}

variable "notify_email" {
  type = string
}

variable "api-name" {
  type    = string
  default = "stevekc-contact-api"
}