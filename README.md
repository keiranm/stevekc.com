# stevekc.com

Personal static site on S3 + CloudFront, with a small serverless backend. Built step by step with the AWS CLI as a refresher on the AWS Developer and Architect material.

## What it does

| Page | Who | What |
| --- | --- | --- |
| `/` | public | homepage with a QR code for https://stevekc.com/ |
| `/file_me/fileme.html` | public | upload any file up to 500 MB, with an optional note |
| `/message_me/messageme.html` | public | anonymous message, delivered by email; the QR code goes on a business card |
| `/inbox/` | `file-admin` only | login, thumbnails, view, keep, permanent delete, tags |

No email ever contains a file or a link to one. Uploads are only visible after login.

## Repo layout

```
index.html, favicons, manifest      homepage and site assets
file_me/fileme.html                 upload page
message_me/messageme.html           message page
inbox/index.html                    login + inbox single page app
lambda/                             one file per Lambda function
layer/                              Pillow layer build notes (see layer/README.md)
docs/architecture.md                diagrams, components, security model, data model
docs/functions.md                   every Lambda: trigger, env vars, behaviour
docs/devnotes.md                    deploy commands, gotchas, decisions, operating notes
```

## Stack

S3, CloudFront, API Gateway (HTTP API, JWT authorizer), Lambda (Python 3.13), EventBridge, DynamoDB, Cognito, SES, Route 53. Region `ap-southeast-2`.

## Deploying

See [docs/devnotes.md](docs/devnotes.md). Every page deploy ends with a CloudFront invalidation.

## Not in this repo

The garage door controller lives in its own project. Its access (Cognito group `family`) is separate from the inbox (`file-admin`).
