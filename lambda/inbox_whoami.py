import json
import os

CORS_HEADERS = {
    "Access-Control-Allow-Origin": os.environ.get('ALLOWED_ORIGIN', 'https://stevekc.com'),
    "Content-Type": "application/json"
}


def groups_from_event(event):
    claims = (event.get('requestContext', {})
                   .get('authorizer', {})
                   .get('jwt', {})
                   .get('claims', {}))
    raw = claims.get('cognito:groups', [])
    if isinstance(raw, list):
        return raw
    # HTTP APIs flatten array claims into a string like "[file-admin family]"
    return [g for g in str(raw).strip('[]').replace(',', ' ').split() if g]


def handler(event, context):
    groups = groups_from_event(event)

    if 'file-admin' not in groups:
        return {
            "statusCode": 403,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "forbidden"})
        }

    return {
        "statusCode": 200,
        "headers": CORS_HEADERS,
        "body": json.dumps({"ok": True, "groups": groups})
    }
