resource "aws_lambda_function" "stevekc-generate-upload-url" {
  function_name = "stevekc-generate-upload-url"
  role          = aws_iam_role.stevekc-generate-upload-url.arn
  handler       = "generate-upload-url.handler"
  runtime       = "python3.13"
  filename      = "${path.module}/../lambda/generate-upload-url.zip"
  timeout       = 10

  environment {
    variables = {
      UPLOAD_BUCKET  = var.bucket_name
      MAX_BYTES      = 524288000
      ALLOWED_ORIGIN = "https://${var.domain}"
    }
  }
}

resource "aws_lambda_function" "stevekc-send-message" {
  function_name = "stevekc-send-message"
  role          = aws_iam_role.stevekc-send-message.arn
  handler       = "send-message.handler"
  runtime       = "python3.13"
  filename      = "${path.module}/../lambda/send-message.zip"
  timeout       = 10

  environment {
    variables = {
      NOTIFY_EMAIL   = var.notify_email
      SEND_FROM      = "${var.domain} uploads <notifications@${var.domain}>"
      ALLOWED_ORIGIN = "https://${var.domain}"
    }
  }
}

resource "aws_lambda_function" "stevekc-notify-upload" {
  function_name = "stevekc-notify-upload"
  role          = aws_iam_role.stevekc-notify-upload.arn
  handler       = "notify-upload.handler"
  runtime       = "python3.13"
  filename      = "${path.module}/../lambda/notify-upload.zip"
  timeout       = 10

  environment {
    variables = {
      NOTIFY_EMAIL = var.notify_email
      SEND_FROM    = "${var.domain} uploads <notifications@${var.domain}>"
      INBOX_TABLE  = var.table_name
      INBOX_URL    = "https://${var.domain}/inbox/"
    }
  }
}

resource "aws_lambda_layer_version" "pillow" {
  filename                 = "${path.module}/../layer/pillow-layer.zip"
  layer_name               = "pillow"
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["x86_64"]
}

resource "aws_lambda_function" "stevekc-generate-thumbnail" {
  function_name = "stevekc-generate-thumbnail"
  role          = aws_iam_role.stevekc-generate-thumbnail.arn
  handler       = "generate-thumbnail.handler"
  runtime       = "python3.13"
  filename      = "${path.module}/../lambda/generate-thumbnail.zip"
  timeout       = 30
  memory_size   = 512
  layers        = [aws_lambda_layer_version.pillow.layer_arn]

  environment {
    variables = {
      INBOX_TABLE = var.table_name
    }
  }
}

resource "aws_lambda_function" "stevekc-inbox-api" {
  function_name = "stevekc-inbox-api"
  role          = aws_iam_role.stevekc-inbox-api.arn
  handler       = "inbox-api.handler"
  runtime       = "python3.13"
  filename      = "${path.module}/../lambda/inbox-api.zip"
  timeout       = 15

  environment {
    variables = {
      INBOX_TABLE    = var.table_name
      UPLOAD_BUCKET  = var.bucket_name
      ALLOWED_ORIGIN = "https://${var.domain}"
    }
  }
}