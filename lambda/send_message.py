import boto3
import os
import json

ses = boto3.client('ses')
NOTIFY_EMAIL = os.environ['NOTIFY_EMAIL']
SEND_FROM = os.environ.get('SEND_FROM', NOTIFY_EMAIL)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": os.environ.get('ALLOWED_ORIGIN', 'https://stevekc.com'),
    "Content-Type": "application/json"
}


def handler(event, context):
    try:
        data = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        data = {}

    message = (data.get('message') or '').strip()[:5000]
    name = (data.get('name') or 'Anonymous').strip()[:100]

    if not message:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "Message is required"})
        }

    ses.send_email(
        Source=SEND_FROM,
        Destination={'ToAddresses': [NOTIFY_EMAIL]},
        Message={
            'Subject': {'Data': f'New message from {name} (stevekc.com)'},
            'Body': {'Text': {'Data': f"From: {name}\n\n{message}"}}
        }
    )

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps({"ok": True})
    }
