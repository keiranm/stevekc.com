
# Trust policy: allow AWS Lambda to assume this role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# stevekc-notify-upload

resource "aws_iam_role" "stevekc-notify-upload" {
  name               = "stevekc-notify-upload-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "stevekc-notify-upload" {
  role       = aws_iam_role.stevekc-notify-upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "stevekc-notify-upload" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.inbox.arn,
      "${aws_dynamodb_table.inbox.arn}/index/*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.files.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "stevekc-notify-upload" {
  name   = "stevekc-notify-upload-policy"
  role   = aws_iam_role.stevekc-notify-upload.id
  policy = data.aws_iam_policy_document.stevekc-notify-upload.json
}

# stevekc-generate-thumbnail

resource "aws_iam_role" "stevekc-generate-thumbnail" {
  name               = "stevekc-generate-thumbnail-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "stevekc-generate-thumbnail" {
  role       = aws_iam_role.stevekc-generate-thumbnail.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "stevekc-generate-thumbnail" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.inbox.arn,
      "${aws_dynamodb_table.inbox.arn}/index/*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.files.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "stevekc-generate-thumbnail" {
  name   = "stevekc-generate-thumbnail-policy"
  role   = aws_iam_role.stevekc-generate-thumbnail.id
  policy = data.aws_iam_policy_document.stevekc-generate-thumbnail.json
}

# stevekc-generate-upload-url

resource "aws_iam_role" "stevekc-generate-upload-url" {
  name               = "stevekc-generate-upload-url-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "stevekc-generate-upload-url" {
  role       = aws_iam_role.stevekc-generate-upload-url.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "stevekc-generate-upload-url" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.files.arn}/uploads/*"
    ]
  }
}

resource "aws_iam_role_policy" "stevekc-generate-upload-url" {
  name   = "stevekc-generate-upload-url-policy"
  role   = aws_iam_role.stevekc-generate-upload-url.id
  policy = data.aws_iam_policy_document.stevekc-generate-upload-url.json
}

# stevekc-inbox-api

resource "aws_iam_role" "stevekc-inbox-api" {
  name               = "stevekc-inbox-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "stevekc-inbox-api" {
  role       = aws_iam_role.stevekc-inbox-api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "stevekc-generate-upload-url" {
  statement {
    effect = "Allow"
    actions = [
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.files.arn}/*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      "${aws_dynamodb_table.inbox.arn}/table/${var.table_name}"
    ]
  }
}

resource "aws_iam_role_policy" "stevekc-inbox-api" {
  name   = "stevekc-inbox-api-policy"
  role   = aws_iam_role.stevekc-inbox-api.id
  policy = data.aws_iam_policy_document.stevekc-inbox-api.json
}

# stevekc-send-message

resource "aws_iam_role" "stevekc-send-message" {
  name               = "stevekc-send-message-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "stevekc-send-message" {
  role       = aws_iam_role.stevekc-send-message.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "stevekc-send-message" {
  statement {
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "stevekc-send-message" {
  name   = "stevekc-send-message-policy"
  role   = aws_iam_role.stevekc-send-message.id
  policy = data.aws_iam_policy_document.stevekc-send-message.json
}
