import boto3
import os
import mimetypes
import urllib.parse
from io import BytesIO
from PIL import Image
from boto3.dynamodb.conditions import Key

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['INBOX_TABLE'])

THUMBNAIL_MAX = (320, 320)
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff'}


def handler(event, context):
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name')
    key = urllib.parse.unquote_plus(detail.get('object', {}).get('key', ''))

    if not bucket or not key:
        return {"statusCode": 200}

    ext = os.path.splitext(key)[1].lower()
    guessed_type, _ = mimetypes.guess_type(key)
    content_type = guessed_type or 'application/octet-stream'

    update_expr = 'SET contentType = :ct'
    expr_values = {':ct': content_type}

    if ext in IMAGE_EXTENSIONS:
        obj = s3.get_object(Bucket=bucket, Key=key)
        img = Image.open(BytesIO(obj['Body'].read()))
        if img.mode in ('RGBA', 'P'):
            img = img.convert('RGB')
        img.thumbnail(THUMBNAIL_MAX)

        buf = BytesIO()
        img.save(buf, format='JPEG', quality=80)
        buf.seek(0)

        thumb_key = f"thumbnails/{key.split('/')[-1]}.jpg"
        s3.put_object(Bucket=bucket, Key=thumb_key, Body=buf, ContentType='image/jpeg')

        update_expr += ', thumbnailKey = :tk'
        expr_values[':tk'] = thumb_key

    resp = table.query(
        IndexName='s3Key-index',
        KeyConditionExpression=Key('s3Key').eq(key)
    )
    items = resp.get('Items', [])
    if items:
        table.update_item(
            Key={'itemId': items[0]['itemId']},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_values
        )

    return {"statusCode": 200}
