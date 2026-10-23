import json
#import boto3

adressee = "stephen.k.clark@gmail.com"

def lambda_handler(event, context):
    client = boto3.client("ses")
    subject = "From Website: " + event['email_subject']
    body = event['email_message'] + "/n sent by: " + event['from_name'] + " " + event['from_address']
    message = {"Subject": {"Data": subject}, "Body": {"Html": {"Data": body}}}
    response = client.send_email(Source = "stephen.k.clark@gmail.com", Destination = {"ToAddresses": [adressee]}, Message = message)          
    resp = {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*",
        },
        "body": response
    }
    
    return resp
