import boto3
import os
import json
import re
import time
from datetime import datetime, timezone

s3 = boto3.client('s3')
BUCKET = os.environ['UPLOAD_BUCKET']
MAX_BYTES = int(os.environ.get('MAX_BYTES', 524288000))

CORS_HEADERS = {
    "Access-Control-Allow-Origin": os.environ.get('ALLOWED_ORIGIN', 'https://stevekc.com'),
    "Content-Type": "application/json"
}


def sanitize(name):
    if not name:
        return None
    name = re.sub(r'[^A-Za-z0-9._-]', '_', name.strip())
    return name[:150] or None


def handler(event, context):
    qs = event.get('queryStringParameters') or {}
    safe_name = sanitize(qs.get('filename'))

    if not safe_name:
        ts = datetime.now(timezone.utc).strftime('%Y%m%d%H%M')
        ext = sanitize(qs.get('ext'))
        safe_name = f"{ts}.{ext}" if ext else ts

    key = f"uploads/pending/{int(time.time())}-{safe_name}"

    try:
        presigned = s3.generate_presigned_post(
            Bucket=BUCKET,
            Key=key,
            Conditions=[
                ["content-length-range", 1, MAX_BYTES],
                ["starts-with", "$x-amz-meta-note", ""]
            ],
            ExpiresIn=300
        )
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e)})
        }

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps({
            "url": presigned["url"],
            "fields": presigned["fields"],
            "maxBytes": MAX_BYTES
        })
    }
