import boto3
import json
import mimetypes
import os
import re
import traceback
from decimal import Decimal
from boto3.dynamodb.conditions import Key
from botocore.config import Config

REGION = os.environ['AWS_REGION']
BUCKET = os.environ['UPLOAD_BUCKET']
URL_TTL = 300  # presigned links live 5 minutes

# SigV4 + regional endpoint so presigned GETs work for an ap-southeast-2 bucket
s3 = boto3.client('s3', region_name=REGION, config=Config(signature_version='s3v4'))
table = boto3.resource('dynamodb').Table(os.environ['INBOX_TABLE'])

CORS_HEADERS = {
    "Access-Control-Allow-Origin": os.environ.get('ALLOWED_ORIGIN', 'https://stevekc.com'),
    "Content-Type": "application/json"
}


def _json_default(o):
    if isinstance(o, Decimal):
        return int(o) if o == o.to_integral_value() else float(o)
    raise TypeError


def respond(status, body):
    return {"statusCode": status, "headers": CORS_HEADERS,
            "body": json.dumps(body, default=_json_default)}


def groups_from_event(event):
    claims = (event.get('requestContext', {}).get('authorizer', {})
                   .get('jwt', {}).get('claims', {}))
    raw = claims.get('cognito:groups', [])
    if isinstance(raw, list):
        return raw
    return [g for g in str(raw).strip('[]').replace(',', ' ').split() if g]


def real_type(item):
    stored = item.get('contentType')
    if stored and stored != 'binary/octet-stream':
        return stored
    guessed, _ = mimetypes.guess_type(item.get('filename', ''))
    return guessed or stored or 'application/octet-stream'


def presign(key, content_type=None):
    params = {'Bucket': BUCKET, 'Key': key}
    if content_type:
        params['ResponseContentType'] = content_type
    return s3.generate_presigned_url('get_object', Params=params, ExpiresIn=URL_TTL)


def get_item(item_id):
    return table.get_item(Key={'itemId': item_id}).get('Item')


def list_items(event):
    qs = event.get('queryStringParameters') or {}
    status = qs.get('status', 'pending')
    if status not in ('pending', 'kept'):
        return respond(400, {"error": "status must be pending or kept"})
    tag = (qs.get('tag') or '').strip().lower()

    kwargs = {'IndexName': 'status-index',
              'KeyConditionExpression': Key('status').eq(status)}
    items = []
    while True:
        resp = table.query(**kwargs)
        items.extend(resp['Items'])
        if 'LastEvaluatedKey' not in resp:
            break
        kwargs['ExclusiveStartKey'] = resp['LastEvaluatedKey']

    if tag:
        items = [i for i in items if tag in i.get('tags', [])]
    items.sort(key=lambda i: i.get('uploadTimestamp', ''), reverse=True)

    out = [{
        'itemId': i['itemId'],
        'filename': i.get('filename'),
        'contentType': real_type(i),
        'size': i.get('size'),
        'uploadTimestamp': i.get('uploadTimestamp'),
        'note': i.get('note', ''),
        'tags': i.get('tags', []),
        'status': i.get('status'),
        'thumbnailUrl': presign(i['thumbnailKey']) if i.get('thumbnailKey') else None
    } for i in items]
    return respond(200, {"items": out})


def view_url(item_id):
    item = get_item(item_id)
    if not item:
        return respond(404, {"error": "not found"})
    return respond(200, {"url": presign(item['s3Key'], real_type(item)), "expiresIn": URL_TTL})


def keep_item(item_id):
    item = get_item(item_id)
    if not item:
        return respond(404, {"error": "not found"})
    if item.get('status') == 'kept':
        return respond(200, {"ok": True})

    src = item['s3Key']
    dst = f"uploads/kept/{src.split('/')[-1]}"
    s3.copy_object(Bucket=BUCKET, Key=dst,
                   CopySource={'Bucket': BUCKET, 'Key': src}, MetadataDirective='COPY')

    expr = 'SET s3Key = :k, #s = :s'
    vals = {':k': dst, ':s': 'kept'}
    old_thumb = item.get('thumbnailKey')
    if old_thumb:
        new_thumb = f"kept-thumbnails/{old_thumb.split('/')[-1]}"
        s3.copy_object(Bucket=BUCKET, Key=new_thumb,
                       CopySource={'Bucket': BUCKET, 'Key': old_thumb}, MetadataDirective='COPY')
        expr += ', thumbnailKey = :t'
        vals[':t'] = new_thumb

    # Record first, then remove the originals: a crash midway leaves a
    # duplicate file, never a record pointing at nothing.
    table.update_item(Key={'itemId': item_id}, UpdateExpression=expr,
                      ExpressionAttributeNames={'#s': 'status'},
                      ExpressionAttributeValues=vals)
    s3.delete_object(Bucket=BUCKET, Key=src)
    if old_thumb:
        s3.delete_object(Bucket=BUCKET, Key=old_thumb)
    return respond(200, {"ok": True})


def delete_item(item_id):
    item = get_item(item_id)
    if not item:
        return respond(404, {"error": "not found"})
    # Files first, then the record: for a permanent delete, never leave
    # the file behind with its record gone.
    s3.delete_object(Bucket=BUCKET, Key=item['s3Key'])
    if item.get('thumbnailKey'):
        s3.delete_object(Bucket=BUCKET, Key=item['thumbnailKey'])
    table.delete_item(Key={'itemId': item_id})
    return respond(200, {"ok": True})


def set_tags(item_id, event):
    try:
        body = json.loads(event.get('body') or '{}')
    except json.JSONDecodeError:
        body = {}
    raw = body.get('tags')
    if not isinstance(raw, list):
        return respond(400, {"error": "tags must be a list"})
    if not get_item(item_id):
        return respond(404, {"error": "not found"})

    clean = []
    for t in raw:
        t = re.sub(r'\s+', ' ', str(t).strip().lower())[:30]
        if t and t not in clean:
            clean.append(t)
    clean = clean[:20]

    table.update_item(Key={'itemId': item_id}, UpdateExpression='SET tags = :t',
                      ExpressionAttributeValues={':t': clean})
    return respond(200, {"tags": clean})


def handler(event, context):
    if 'file-admin' not in groups_from_event(event):
        return respond(403, {"error": "forbidden"})

    route = event.get('routeKey')
    item_id = (event.get('pathParameters') or {}).get('itemId')

    try:
        if route == 'GET /inbox/items':
            return list_items(event)
        if route == 'GET /inbox/items/{itemId}/url':
            return view_url(item_id)
        if route == 'POST /inbox/items/{itemId}/keep':
            return keep_item(item_id)
        if route == 'POST /inbox/items/{itemId}/tags':
            return set_tags(item_id, event)
        if route == 'DELETE /inbox/items/{itemId}':
            return delete_item(item_id)
    except Exception:
        traceback.print_exc()  # details go to CloudWatch, not to the client
        return respond(500, {"error": "server error"})

    return respond(404, {"error": "unknown route"})
