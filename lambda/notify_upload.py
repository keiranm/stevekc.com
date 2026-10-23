import boto3
import os
import uuid
import urllib.parse
from datetime import datetime, timezone

s3 = boto3.client('s3')
ses = boto3.client('ses')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['INBOX_TABLE'])

NOTIFY_EMAIL = os.environ['NOTIFY_EMAIL']
SEND_FROM = os.environ.get('SEND_FROM', NOTIFY_EMAIL)
INBOX_URL = os.environ.get('INBOX_URL', 'https://stevekc.com/inbox/')


def handler(event, context):
    # EventBridge delivers one event per invocation as a flat "detail"
    # object — not the old S3-native "Records" list shape.
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name')
    key = urllib.parse.unquote_plus(detail.get('object', {}).get('key', ''))

    if not bucket or not key:
        return {"statusCode": 200}

    head = s3.head_object(Bucket=bucket, Key=key)
    note = head.get('Metadata', {}).get('note', '')
    content_type = head.get('ContentType', 'application/octet-stream')
    size = detail.get('object', {}).get('size', 0)

    filename = key.split('/')[-1]
    item_id = str(uuid.uuid4())

    table.put_item(Item={
        'itemId': item_id,
        's3Key': key,
        'filename': filename,
        'contentType': content_type,
        'size': size,
        'uploadTimestamp': datetime.now(timezone.utc).isoformat(),
        'note': note,
        'status': 'pending',
        'tags': []
    })

    ses.send_email(
        Source=SEND_FROM,
        Destination={'ToAddresses': [NOTIFY_EMAIL]},
        Message={
            'Subject': {'Data': 'New item in your inbox'},
            'Body': {'Text': {'Data': f'Something new is waiting for review:\n{INBOX_URL}\n'}}
        }
    )

    return {"statusCode": 200}
