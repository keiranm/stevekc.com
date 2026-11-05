resource "aws_dynamodb_table" "inbox" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "itemId"
  attribute {
    name = "itemId"
    type = "HASH"
  }
  attribute {
    name = "status"
    type = "S"
  }
  attribute {
    name = "s3Key"
    type = "S"
  }
  global_secondary_index {
    name = "status-index"
    key_schema {
      attribute_name = "status"
      key_type       = "HASH"
    }
    projection_type = "ALL"
  }
  global_secondary_index {
    name = "s3Key-index"
    key_schema {
      attribute_name = "s3Key"
      key_type       = "HASH"
    }
    projection_type = "ALL"
  }
}