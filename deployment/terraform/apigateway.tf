resource "aws_apigatewayv2_api" "stevekc-contact-api" {
  name          = var.api-name
  protocol_type = "HTTP"
  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_origins = ["https://${var.domain}"]
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.stevekc-contact-api.id
  authorizer_type  = "JWT"
  name             = "stevekc-cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.stevekc-web.id]
    issuer   = "https://${aws_cognito_user_pool.stevekc-users.endpoint}"
  }
}

resource "aws_apigatewayv2_integration" "upload_url" {
  api_id                 = aws_apigatewayv2_api.stevekc-contact-api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.stevekc-generate-upload-url.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "send_message" {
  api_id                 = aws_apigatewayv2_api.stevekc-contact-api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.stevekc-send-message.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "inbox_api" {
  api_id                 = aws_apigatewayv2_api.stevekc-contact-api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.stevekc-inbox-api.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_url" {
  api_id    = aws_apigatewayv2_api.stevekc-contact-api.id
  route_key = "GET /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.upload_url.id}"
}

resource "aws_apigatewayv2_route" "send_message" {
  api_id    = aws_apigatewayv2_api.stevekc-contact-api.id
  route_key = "POST /message"
  target    = "integrations/${aws_apigatewayv2_integration.send_message.id}"
}

resource "aws_apigatewayv2_route" "inbox" {
  for_each = toset([
    "GET /inbox/items",
    "GET /inbox/items/{itemId}/url",
    "POST /inbox/items/{itemId}/keep",
    "POST /inbox/items/{itemId}/tags",
    "DELETE /inbox/items/{itemId}",
  ])

  api_id             = aws_apigatewayv2_api.stevekc-contact-api.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.inbox_api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.stevekc-contact-api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "upload_url_apigateway" {
  statement_id  = "apigw-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stevekc-generate-upload-url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stevekc-contact-api.execution_arn}/*/*/upload-url"
}

resource "aws_lambda_permission" "send_message_apigateway" {
  statement_id  = "apigw-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stevekc-send-message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stevekc-contact-api.execution_arn}/*/*/message"
}

resource "aws_lambda_permission" "inbox_api_apigateway" {
  statement_id  = "apigw-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stevekc-inbox-api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.stevekc-contact-api.execution_arn}/*/*/inbox/*"
}

