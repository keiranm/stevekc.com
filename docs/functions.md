# Functions

All Lambdas are Python 3.13 and run under the shared role `stevekc-upload-lambda-role`.

| Function (AWS name) | File | Trigger | Environment variables |
| --- | --- | --- | --- |
| stevekc-generate-upload-url | `lambda/generate_upload_url.py` | `GET /upload-url` | `UPLOAD_BUCKET`, `MAX_BYTES`, `ALLOWED_ORIGIN` |
| stevekc-send-message | `lambda/send_message.py` | `POST /message` | `NOTIFY_EMAIL`, `SEND_FROM`, `ALLOWED_ORIGIN` |
| stevekc-notify-upload | `lambda/notify_upload.py` | EventBridge, Object Created in `uploads/pending/` | `NOTIFY_EMAIL`, `SEND_FROM`, `INBOX_TABLE`, `INBOX_URL` |
| stevekc-generate-thumbnail | `lambda/generate_thumbnail.py` | same EventBridge rule | `INBOX_TABLE`; Pillow layer, 512 MB, 30 s |
| stevekc-inbox-api | `lambda/inbox_api.py` | the `/inbox/items` routes (JWT authorizer) | `UPLOAD_BUCKET`, `INBOX_TABLE`, `ALLOWED_ORIGIN` |

## generate_upload_url

Returns a presigned POST for `uploads/pending/{epoch}-{safe_name}`. Conditions: `content-length-range` 1 byte to 500 MB, and `x-amz-meta-note` may carry any text. Expires in 5 minutes. With no usable filename it falls back to `YYYYMMDDHHMM` plus the extension.

## send_message

Takes `{name, message}` as JSON, truncates to 100 and 5000 characters, and emails Steve through SES. Returns 400 if the message is empty.

## notify_upload

Reads `event['detail']` (EventBridge shape, not `Records`), calls `head_object` for the note and content type, writes the DynamoDB record with status `pending`, and sends a bare "new item" email with only the inbox URL.

## generate_thumbnail

For image extensions, makes a JPEG thumbnail (longest side 320 px, aspect kept) into `thumbnails/{name}.jpg`, finds the record through `s3Key-index`, and updates `contentType` and `thumbnailKey`.

## inbox_api

One handler dispatching on `routeKey`. Returns 403 unless `file-admin` is in the groups claim.

| Route | Function | Behaviour |
| --- | --- | --- |
| `GET /inbox/items` | `list_items` | query `status-index` (`?status=pending` by default, or `kept`; optional `?tag=`), newest first, with 5-minute thumbnail URLs |
| `GET /inbox/items/{itemId}/url` | `view_url` | presigned GET with the correct `ResponseContentType` |
| `POST /inbox/items/{itemId}/keep` | `keep_item` | copy to `uploads/kept/` and `kept-thumbnails/`, update the record, delete the originals |
| `POST /inbox/items/{itemId}/tags` | `set_tags` | lowercase, trim, dedupe, max 20 tags of 30 characters |
| `DELETE /inbox/items/{itemId}` | `delete_item` | delete files first, then the record |

Helpers: `groups_from_event` (parses list or string claims), `real_type` (falls back to the extension when the stored type is binary), `presign`.

## Pages

| Page | Notes |
| --- | --- |
| `file_me/fileme.html` | drag and drop, progress bar over XHR, note sent as `x-amz-meta-note` before the file field |
| `message_me/messageme.html` | QR code, name and message form posting to `/message` |
| `inbox/index.html` | Cognito login from the browser, `sessionStorage` tokens with silent refresh, pending/kept tabs, tag filter, keep, two-click delete, DOM built with `textContent` |
