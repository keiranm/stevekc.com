resource "aws_s3_bucket_notification" "notification" {
  bucket      = aws_s3_bucket.stevekc-uploads.id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "upload_pending" {
  name = "stevekc-upload_pending"
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]

    detail = {
      bucket = {
        name = ["${aws_s3_bucket.stevekc-uploads.id}"]
      }

      object = {
        key = [
          {
            prefix = "uploads/pending/"
          }
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "notify_upload" {
  rule = aws_cloudwatch_event_rule.upload_pending.name
  arn  = aws_lambda_function.stevekc-notify-upload.arn
  id   = "notify"
}

resource "aws_cloudwatch_event_target" "generate_thumbnail" {
  rule = aws_cloudwatch_event_rule.upload_pending.name
  arn  = aws_lambda_function.stevekc-generate-thumbnail.arn
  id   = "thumbnail"
}

resource "aws_lambda_permission" "notify_upload_eventbridge" {
  statement_id  = "eventbridge-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stevekc-notify-upload.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.upload_pending.arn
}

resource "aws_lambda_permission" "generate_thumbnail_eventbridge" {
  statement_id  = "eventbridge-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stevekc-generate-thumbnail.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.upload_pending.arn
}