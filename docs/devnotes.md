# Devnotes

## Deploying

Run from the repo root. Every page deploy ends with a CloudFront invalidation, or the old page keeps being served.

```
aws s3 cp inbox/index.html s3://stevekc.com/inbox/index.html --content-type "text/html; charset=utf-8" \
&& aws cloudfront create-invalidation --distribution-id E2T8UBLN7C8V11 --paths "/inbox/*" "/inbox/"
```

Other pages: `file_me/fileme.html`, `message_me/messageme.html`, `index.html`. Use the matching path in both commands.

A Lambda:

```
cd lambda && zip -q inbox_api.zip inbox_api.py && aws lambda update-function-code --function-name stevekc-inbox-api --zip-file fileb://inbox_api.zip
```

The thumbnail Lambda needs the Pillow layer and 512 MB. Before testing a deploy, check that the local file is the one you deployed: an old `fileme.html` in S3 once looked exactly like a CloudFront cache problem.

## Gotchas

| Symptom | Cause | Fix |
| --- | --- | --- |
| notification email lands in spam | Gmail DMARC rejects a gmail.com sender sent through SES | send from the verified stevekc.com domain with Easy DKIM |
| DKIM stuck on FAILED | SES stopped checking after 72 hours in 2024 | delete and recreate the identity, republish the CNAMEs |
| upload fails with "Policy Condition failed: starts-with $x-amz-meta-note" | an old `fileme.html` was still in S3 | redeploy the current file |
| S3 refuses a second Lambda on the same prefix | S3 notifications cannot fan one event out to two Lambdas | EventBridge rule on Object Created |
| Lambdas run 6 ms and do nothing | EventBridge events carry `event['detail']`, not `event['Records']` | read bucket and key from `detail` |
| inbox 403 on a valid token | HTTP APIs flatten the groups claim to a string like `[file-admin family]` | parse both a list and a string |
| non-image items show binary/octet-stream | the two upload Lambdas race to set the content type | correct at read time from the extension; set `ResponseContentType` on view URLs |
| thumbnail missing on one item | thumbnail Lambda ran before the record existed | seen once; open item |
| token call fails as invalid | a placeholder password was used literally | read the password with `read -s "PW?prompt: "` |
| zsh does not split `$VAR` | unquoted variables are not word-split in zsh | build JSON with Python or quote carefully |
| `watch` not found | macOS has none | `while` loop with `sleep` |

## Decisions

- No file link in email: uploads may be sensitive, so the email is a bare "something new".
- Built step by step with the CLI rather than one deploy script, as a learning exercise.
- Tokens in `sessionStorage` only, so closing the tab signs out.
- Only `file-admin` sees uploads. `family` is for garage access, in the garage project.
- No video thumbnails: videos get a generic icon and the browser plays them; use `aws s3 cp` if playback fails.
- Pending items and their thumbnails expire after 90 days; kept items never expire.
- Logins use `+home` aliases (stephen.k.clark+home@gmail.com), easy to filter and apart from the root account email.

## Operating

- Pending check: `aws s3 ls s3://stevekc-uploads/uploads/pending/` should be empty unless something is waiting. An object there with no DynamoDB record is an orphan.
- Lifecycle check: `aws s3api get-bucket-lifecycle-configuration --bucket stevekc-uploads` should show only `expire-pending` and `expire-pending-thumbnails`. A rule on plain `uploads/` would delete kept files.
- Pull a file down: `aws s3 cp s3://stevekc-uploads/uploads/kept/<name> .`
- Use a known dev password while building, then set a real one. Run `unset PW TOKEN` after sessions that used them.
- Never commit command output from `aws` calls that return credentials or presigned fields (see below).
