resource "aws_cognito_user_pool" "stevekc-users" {
  name                     = var.pool_name
  auto_verified_attributes = "email"
  username_attributes      = "email"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "stevekc-web" {
  name            = "stevekc-web"
  user_pool_id    = aws_cognito_user_pool.stevekc-users.id
  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}

resource "aws_cognito_user_group" "file-admin" {
  name         = "file-admin"
  user_pool_id = aws_cognito_user_pool.stevekc-users.id
  description  = "Full access to the file inbox"
}

resource "aws_cognito_user_group" "family" {
  name         = "family"
  user_pool_id = aws_cognito_user_pool.stevekc-users.id
  description  = "Garage door access only"
}

resource "aws_cognito_user" "admin" {
  username     = var.admin_email
  user_pool_id = aws_cognito_user_pool.stevekc-users.id
  attributes = {
    name           = "email"
    email          = var.admin_email
    email_verified = true
  }
  password = var.admin_email_password
}

resource "aws_cognito_user_in_group" "file-admin" {
  user_pool_id = aws_cognito_user_pool.stevekc-users.id
  username     = aws_cognito_user.admin.username
  group_name   = aws_cognito_user_group.file-admin.name
}

resource "aws_cognito_user_in_group" "family" {
  user_pool_id = aws_cognito_user_pool.stevekc-users.id
  username     = aws_cognito_user.admin.username
  group_name   = aws_cognito_user_group.family.name
}