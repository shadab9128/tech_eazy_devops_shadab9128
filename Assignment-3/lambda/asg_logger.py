import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
bucket_name = os.environ['BUCKET']
prefix = os.environ.get('PREFIX', 'asg-events/')

def handler(event, context):
    print("Received event:", json.dumps(event))

    # Parse SNS message
    for record in event['Records']:
        sns_message = record['Sns']['Message']
        timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H-%M-%SZ")
        key = f"{prefix}{timestamp}.json"

        try:
            s3.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=sns_message.encode("utf-8"),
                ContentType="application/json"
            )
            print(f"✅ Logged ASG event to s3://{bucket_name}/{key}")
        except Exception as e:
            print(f"❌ Error writing to S3: {e}")

    return {"statusCode": 200, "body": "Event logged successfully"}
