# Build commands

The AWS CLI commands used to build the stevekc.com upload, message and inbox features, in the order they were run, cleaned up to the final working state. Dead ends, retries and polling loops are left out, with the lessons noted where they matter.

No secrets are in this file. Passwords are read with `read -s`, DKIM tokens are fetched at run time, and account details are variables. The Lambda source files live in `lambda/`.

Assumes the static site already exists (S3 bucket `stevekc.com` behind CloudFront `E2T8UBLN7C8V11`, DNS in Route 53) and the AWS CLI is configured. Shell is zsh on macOS.

## 0. Variables

Set these once per shell session and run everything from the repo root.

```bash
REGION=ap-southeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DOMAIN=stevekc.com
BUCKET=stevekc-uploads
ROLE=stevekc-upload-lambda-role
NOTIFY_EMAIL=you@example.com            # where notifications go
ADMIN_EMAIL=you+home@example.com        # inbox login
CF_DIST=E2T8UBLN7C8V11
TABLE=stevekc-file-inbox
```

## 1. SES: verify the recipient and the sending domain

The account starts in the SES sandbox, which only restricts sending to unverified recipients. Every email goes to `NOTIFY_EMAIL`, so verifying that address is enough.

```bash
aws sesv2 get-account --region $REGION --query 'ProductionAccessEnabled'
aws ses verify-email-identity --email-address $NOTIFY_EMAIL --region $REGION   # click the emailed link
```

Mail sent From a gmail.com address through SES lands in spam (Gmail DMARC). Send from the domain with DKIM instead:

```bash
aws sesv2 create-email-identity --email-identity $DOMAIN --region $REGION

ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN. --query "HostedZones[0].Id" --output text)
aws sesv2 get-email-identity --email-identity $DOMAIN --region $REGION \
  --query "DkimAttributes.Tokens" --output json > /tmp/dkim-tokens.json

python3 -c "
import json
tokens = json.load(open('/tmp/dkim-tokens.json'))
changes = [{'Action': 'UPSERT', 'ResourceRecordSet': {
    'Name': f'{t}._domainkey.$DOMAIN', 'Type': 'CNAME', 'TTL': 300,
    'ResourceRecords': [{'Value': f'{t}.dkim.amazonses.com'}]}} for t in tokens]
json.dump({'Changes': changes}, open('/tmp/dkim-change-batch.json', 'w'), indent=2)
"
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/dkim-change-batch.json

# wait for SUCCESS (macOS has no `watch`)
while true; do
  STATUS=$(aws sesv2 get-email-identity --email-identity $DOMAIN --region $REGION --query "DkimAttributes.Status" --output text)
  echo "$(date '+%H:%M:%S') $STATUS"; [ "$STATUS" = "SUCCESS" ] && break; sleep 30
done
```

Lesson: if DKIM stays on FAILED for hours, SES has stopped checking. Delete the identity (`delete-email-identity`), delete the old CNAMEs, then repeat the block above.

## 2. The private bucket

```bash
aws s3api create-bucket --bucket $BUCKET --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION

aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

cat > /tmp/upload-cors.json <<EOF
{"CORSRules": [{"AllowedOrigins": ["https://$DOMAIN"], "AllowedMethods": ["POST", "PUT", "GET"],
  "AllowedHeaders": ["*"], "ExposeHeaders": ["ETag"], "MaxAgeSeconds": 3000}]}
EOF
aws s3api put-bucket-cors --bucket $BUCKET --cors-configuration file:///tmp/upload-cors.json

# pending uploads and their thumbnails expire after 90 days; kept files never expire.
# Do NOT put a rule on plain "uploads/": it would delete kept files.
cat > /tmp/upload-lifecycle.json <<'EOF'
{"Rules": [
  {"ID": "expire-pending", "Filter": {"Prefix": "uploads/pending/"}, "Status": "Enabled", "Expiration": {"Days": 90}},
  {"ID": "expire-pending-thumbnails", "Filter": {"Prefix": "thumbnails/"}, "Status": "Enabled", "Expiration": {"Days": 90}}
]}
EOF
aws s3api put-bucket-lifecycle-configuration --bucket $BUCKET --lifecycle-configuration file:///tmp/upload-lifecycle.json
```

## 3. DynamoDB table

```bash
aws dynamodb create-table --table-name $TABLE --region $REGION \
  --attribute-definitions AttributeName=itemId,AttributeType=S AttributeName=status,AttributeType=S \
  --key-schema AttributeName=itemId,KeyType=HASH \
  --global-secondary-indexes '[{"IndexName":"status-index","KeySchema":[{"AttributeName":"status","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}]' \
  --billing-mode PAY_PER_REQUEST

aws dynamodb update-table --table-name $TABLE --region $REGION \
  --attribute-definitions AttributeName=s3Key,AttributeType=S \
  --global-secondary-index-updates '[{"Create":{"IndexName":"s3Key-index","KeySchema":[{"AttributeName":"s3Key","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}}]'
# only one index can be created per update-table call; wait for ACTIVE
aws dynamodb describe-table --table-name $TABLE --region $REGION --query "Table.GlobalSecondaryIndexes[].[IndexName,IndexStatus]" --output text
```

## 4. IAM role shared by all Lambdas

```bash
cat > /tmp/trust-policy.json <<'EOF'
{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}
EOF
aws iam create-role --role-name $ROLE --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# S3 and SES
cat > /tmp/p1.json <<EOF
{"Version": "2012-10-17", "Statement": [
  {"Effect": "Allow", "Action": ["s3:PutObject", "s3:GetObject"], "Resource": "arn:aws:s3:::$BUCKET/*"},
  {"Effect": "Allow", "Action": ["ses:SendEmail", "ses:SendRawEmail"], "Resource": "*"}]}
EOF
aws iam put-role-policy --role-name $ROLE --policy-name stevekc-upload-lambda-policy --policy-document file:///tmp/p1.json

# DynamoDB: notify writes
cat > /tmp/p2.json <<EOF
{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["dynamodb:PutItem"],
  "Resource": "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$TABLE"}]}
EOF
aws iam put-role-policy --role-name $ROLE --policy-name stevekc-dynamo-write-policy --policy-document file:///tmp/p2.json

# DynamoDB: thumbnail and inbox queries and updates (indexes included)
cat > /tmp/p3.json <<EOF
{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": ["dynamodb:Query", "dynamodb:UpdateItem"],
  "Resource": ["arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$TABLE", "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$TABLE/index/*"]}]}
EOF
aws iam put-role-policy --role-name $ROLE --policy-name stevekc-dynamo-query-update-policy --policy-document file:///tmp/p3.json

# inbox: permanent delete and record lookups
cat > /tmp/p4.json <<EOF
{"Version": "2012-10-17", "Statement": [
  {"Effect": "Allow", "Action": ["s3:DeleteObject"], "Resource": "arn:aws:s3:::$BUCKET/*"},
  {"Effect": "Allow", "Action": ["dynamodb:GetItem", "dynamodb:DeleteItem"], "Resource": "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$TABLE"}]}
EOF
aws iam put-role-policy --role-name $ROLE --policy-name stevekc-inbox-policy --policy-document file:///tmp/p4.json

ROLE_ARN=$(aws iam get-role --role-name $ROLE --query 'Role.Arn' --output text)
```

## 5. Pillow layer (for thumbnails)

```bash
mkdir -p layer/python
pip3 install pillow --platform manylinux2014_x86_64 --target layer/python \
  --implementation cp --python-version 3.13 --only-binary=:all: --upgrade
(cd layer && zip -qr pillow-layer.zip python)

LAYER_ARN=$(aws lambda publish-layer-version --layer-name pillow \
  --zip-file fileb://layer/pillow-layer.zip --compatible-runtimes python3.13 \
  --compatible-architectures x86_64 --region $REGION --query 'LayerVersionArn' --output text)
```

## 6. The Lambda functions

Each function is a zip of one file from `lambda/`.

```bash
for FN in generate_upload_url send_message notify_upload generate_thumbnail inbox_api; do
  (cd lambda && zip -q $FN.zip $FN.py)
done

aws lambda create-function --function-name stevekc-generate-upload-url --runtime python3.13 \
  --handler generate_upload_url.handler --role $ROLE_ARN --zip-file fileb://lambda/generate_upload_url.zip \
  --timeout 10 --region $REGION \
  --environment "Variables={UPLOAD_BUCKET=$BUCKET,MAX_BYTES=524288000,ALLOWED_ORIGIN=https://$DOMAIN}"

aws lambda create-function --function-name stevekc-send-message --runtime python3.13 \
  --handler send_message.handler --role $ROLE_ARN --zip-file fileb://lambda/send_message.zip \
  --timeout 10 --region $REGION \
  --environment "Variables={NOTIFY_EMAIL=$NOTIFY_EMAIL,SEND_FROM=stevekc.com messages <notifications@$DOMAIN>,ALLOWED_ORIGIN=https://$DOMAIN}"

aws lambda create-function --function-name stevekc-notify-upload --runtime python3.13 \
  --handler notify_upload.handler --role $ROLE_ARN --zip-file fileb://lambda/notify_upload.zip \
  --timeout 10 --region $REGION \
  --environment "Variables={NOTIFY_EMAIL=$NOTIFY_EMAIL,SEND_FROM=stevekc.com uploads <notifications@$DOMAIN>,INBOX_TABLE=$TABLE,INBOX_URL=https://$DOMAIN/inbox/}"

aws lambda create-function --function-name stevekc-generate-thumbnail --runtime python3.13 \
  --handler generate_thumbnail.handler --role $ROLE_ARN --zip-file fileb://lambda/generate_thumbnail.zip \
  --timeout 30 --memory-size 512 --layers $LAYER_ARN --region $REGION \
  --environment "Variables={INBOX_TABLE=$TABLE}"

aws lambda create-function --function-name stevekc-inbox-api --runtime python3.13 \
  --handler inbox_api.handler --role $ROLE_ARN --zip-file fileb://lambda/inbox_api.zip \
  --timeout 15 --region $REGION \
  --environment "Variables={UPLOAD_BUCKET=$BUCKET,INBOX_TABLE=$TABLE,ALLOWED_ORIGIN=https://$DOMAIN}"
```

Updating code later (the same pattern for each function):

```bash
(cd lambda && zip -q notify_upload.zip notify_upload.py)
aws lambda update-function-code --function-name stevekc-notify-upload --zip-file fileb://lambda/notify_upload.zip --region $REGION
```

## 7. S3 upload event to both Lambdas (EventBridge)

S3 cannot send one event to two Lambdas on the same prefix ("overlapping suffixes"), so S3 notifies EventBridge and a rule fans out. EventBridge events arrive as `event['detail']`, not `event['Records']`. Replace any existing S3 Lambda notifications with this one setting:

```bash
aws s3api put-bucket-notification-configuration --bucket $BUCKET \
  --notification-configuration '{"EventBridgeConfiguration": {}}'

cat > /tmp/event-pattern.json <<EOF
{"source": ["aws.s3"], "detail-type": ["Object Created"],
 "detail": {"bucket": {"name": ["$BUCKET"]}, "object": {"key": [{"prefix": "uploads/pending/"}]}}}
EOF
aws events put-rule --name stevekc-upload-pending-rule --event-pattern file:///tmp/event-pattern.json --region $REGION

NOTIFY_ARN=$(aws lambda get-function --function-name stevekc-notify-upload --region $REGION --query 'Configuration.FunctionArn' --output text)
THUMB_ARN=$(aws lambda get-function --function-name stevekc-generate-thumbnail --region $REGION --query 'Configuration.FunctionArn' --output text)
aws events put-targets --rule stevekc-upload-pending-rule --region $REGION \
  --targets "[{\"Id\":\"notify\",\"Arn\":\"$NOTIFY_ARN\"},{\"Id\":\"thumbnail\",\"Arn\":\"$THUMB_ARN\"}]"

RULE_ARN=$(aws events describe-rule --name stevekc-upload-pending-rule --region $REGION --query 'Arn' --output text)
for FN in stevekc-notify-upload stevekc-generate-thumbnail; do
  aws lambda add-permission --function-name $FN --statement-id eventbridge-invoke \
    --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn "$RULE_ARN" --region $REGION
done
```

Test: `aws s3 cp /tmp/test.txt s3://$BUCKET/uploads/pending/manual-test.txt`, then check the email arrives and `aws dynamodb scan --table-name $TABLE` shows the record. A Lambda that runs in a few milliseconds and does nothing is reading the wrong event shape.

## 8. Cognito: user pool, client, groups, user

```bash
POOL_ID=$(aws cognito-idp create-user-pool --pool-name stevekc-users \
  --auto-verified-attributes email --username-attributes email \
  --admin-create-user-config AllowAdminCreateUserOnly=true \
  --policies '{"PasswordPolicy":{"MinimumLength":10,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":false}}' \
  --region $REGION --query 'UserPool.Id' --output text)

# public client: no secret, because the browser calls Cognito directly
CLIENT_ID=$(aws cognito-idp create-user-pool-client --user-pool-id $POOL_ID --client-name stevekc-web \
  --no-generate-secret --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --region $REGION --query 'UserPoolClient.ClientId' --output text)

aws cognito-idp create-group --group-name file-admin --user-pool-id $POOL_ID --description "Full access to the file inbox" --region $REGION
aws cognito-idp create-group --group-name family     --user-pool-id $POOL_ID --description "Garage door access only" --region $REGION

aws cognito-idp admin-create-user --user-pool-id $POOL_ID --username $ADMIN_EMAIL \
  --user-attributes Name=email,Value=$ADMIN_EMAIL Name=email_verified,Value=true \
  --message-action SUPPRESS --region $REGION

read -s "PW?password: "; echo      # never type a password inline or commit one
aws cognito-idp admin-set-user-password --user-pool-id $POOL_ID --username $ADMIN_EMAIL \
  --password "$PW" --permanent --region $REGION
unset PW

aws cognito-idp admin-add-user-to-group --user-pool-id $POOL_ID --username $ADMIN_EMAIL --group-name file-admin --region $REGION
aws cognito-idp admin-add-user-to-group --user-pool-id $POOL_ID --username $ADMIN_EMAIL --group-name family --region $REGION
```

Do the create-user step before the set-password step, or the password call fails with "user does not exist".

## 9. HTTP API: public routes

```bash
API_ID=$(aws apigatewayv2 create-api --name stevekc-contact-api --protocol-type HTTP \
  --cors-configuration AllowOrigins=https://$DOMAIN,AllowMethods=GET,POST,OPTIONS,AllowHeaders=content-type \
  --region $REGION --query 'ApiId' --output text)

UPLOAD_ARN=$(aws lambda get-function --function-name stevekc-generate-upload-url --region $REGION --query 'Configuration.FunctionArn' --output text)
MSG_ARN=$(aws lambda get-function --function-name stevekc-send-message --region $REGION --query 'Configuration.FunctionArn' --output text)

UPLOAD_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY \
  --integration-uri "$UPLOAD_ARN" --payload-format-version 2.0 --region $REGION --query 'IntegrationId' --output text)
MSG_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY \
  --integration-uri "$MSG_ARN" --payload-format-version 2.0 --region $REGION --query 'IntegrationId' --output text)

aws apigatewayv2 create-route --api-id $API_ID --route-key "GET /upload-url" --target "integrations/$UPLOAD_INT" --region $REGION
aws apigatewayv2 create-route --api-id $API_ID --route-key "POST /message"   --target "integrations/$MSG_INT" --region $REGION
aws apigatewayv2 create-stage --api-id $API_ID --stage-name '$default' --auto-deploy --region $REGION

aws lambda add-permission --function-name stevekc-generate-upload-url --statement-id apigw-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/upload-url" --region $REGION
aws lambda add-permission --function-name stevekc-send-message --statement-id apigw-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/message" --region $REGION

API_ENDPOINT="https://$API_ID.execute-api.$REGION.amazonaws.com"
curl "$API_ENDPOINT/upload-url?filename=curltest.jpg"
curl -X POST "$API_ENDPOINT/message" -H "Content-Type: application/json" -d '{"name":"Curl Test","message":"hello via API Gateway"}'
```

Put `$API_ENDPOINT` into `API_BASE` in `fileme.html`, `messageme.html` and `inbox/index.html`.

## 10. HTTP API: login-protected inbox routes

```bash
AUTH_ID=$(aws apigatewayv2 create-authorizer --api-id $API_ID --authorizer-type JWT --name stevekc-cognito \
  --identity-source '$request.header.Authorization' \
  --jwt-configuration Audience=$CLIENT_ID,Issuer=https://cognito-idp.$REGION.amazonaws.com/$POOL_ID \
  --region $REGION --query AuthorizerId --output text)

# the inbox sends an Authorization header and DELETE requests
aws apigatewayv2 update-api --api-id $API_ID --region $REGION \
  --cors-configuration "{\"AllowOrigins\":[\"https://$DOMAIN\"],\"AllowMethods\":[\"GET\",\"POST\",\"DELETE\",\"OPTIONS\"],\"AllowHeaders\":[\"content-type\",\"authorization\"]}"

INBOX_ARN=$(aws lambda get-function --function-name stevekc-inbox-api --region $REGION --query 'Configuration.FunctionArn' --output text)
INBOX_INT=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY \
  --integration-uri "$INBOX_ARN" --payload-format-version 2.0 --region $REGION --query 'IntegrationId' --output text)

for ROUTE in "GET /inbox/items" "GET /inbox/items/{itemId}/url" "POST /inbox/items/{itemId}/keep" \
             "POST /inbox/items/{itemId}/tags" "DELETE /inbox/items/{itemId}"; do
  aws apigatewayv2 create-route --api-id $API_ID --route-key "$ROUTE" --target "integrations/$INBOX_INT" \
    --authorization-type JWT --authorizer-id $AUTH_ID --region $REGION --query "RouteKey" --output text
done

aws lambda add-permission --function-name stevekc-inbox-api --statement-id apigw-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/inbox/*" --region $REGION
```

The authorizer only checks that the token is valid. The group check (`file-admin`) is in `inbox_api.py`, which returns 403 otherwise. HTTP APIs flatten the groups claim into a string like `[file-admin family]`, so the Lambda parses both a list and a string.

## 11. Test the inbox API

```bash
read -s "PW?password: "; echo
TOKEN=$(aws cognito-idp initiate-auth --client-id $CLIENT_ID --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=$ADMIN_EMAIL,PASSWORD="$PW" --region $REGION \
  --query "AuthenticationResult.IdToken" --output text)
unset PW

curl -i "$API_ENDPOINT/inbox/items"                                          # 401 without a token
curl -s -H "Authorization: Bearer $TOKEN" "$API_ENDPOINT/inbox/items?status=pending" | python3 -m json.tool

ITEM=<an itemId from the list>
curl -s -H "Authorization: Bearer $TOKEN" "$API_ENDPOINT/inbox/items/$ITEM/url"
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d '{"tags":["holiday"]}' "$API_ENDPOINT/inbox/items/$ITEM/tags"
curl -s -X POST -H "Authorization: Bearer $TOKEN" "$API_ENDPOINT/inbox/items/$ITEM/keep"
curl -s -H "Authorization: Bearer $TOKEN" "$API_ENDPOINT/inbox/items?status=kept&tag=holiday"
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$API_ENDPOINT/inbox/items/$ITEM"

unset TOKEN
```

To prove the group check, create a throwaway user in the `family` group only. Its token should get 403, then delete the user with `admin-delete-user`.

## 12. Deploy the pages

Every deploy ends with a CloudFront invalidation.

```bash
aws s3 cp index.html s3://$DOMAIN/index.html
aws s3 cp file_me/fileme.html s3://$DOMAIN/file_me/fileme.html
aws s3 cp message_me/messageme.html s3://$DOMAIN/message_me/messageme.html
aws s3 cp inbox/index.html s3://$DOMAIN/inbox/index.html --content-type "text/html; charset=utf-8"

aws cloudfront create-invalidation --distribution-id $CF_DIST \
  --paths "/index.html" "/" "/file_me/*" "/message_me/*" "/inbox/*" "/inbox/"
```

Check the file you deployed is the one you edited: an old `fileme.html` in S3 once looked exactly like a cache problem.

## 13. Cleanup performed afterwards

```bash
aws s3 rm s3://$BUCKET/uploads/pending/<orphaned-test-object>

# remove a test Lambda, its route, its integration and its logs
aws apigatewayv2 delete-route --api-id $API_ID --route-id <route-id>
aws apigatewayv2 delete-integration --api-id $API_ID --integration-id <integration-id>
aws lambda delete-function --function-name <function-name>
aws logs delete-log-group --log-group-name /aws/lambda/<function-name>
```

## Changing a password

```bash
read -s "NEWPW?new password: "; echo
aws cognito-idp admin-set-user-password --user-pool-id $POOL_ID --username $ADMIN_EMAIL \
  --password "$NEWPW" --permanent --region $REGION
unset NEWPW
```
