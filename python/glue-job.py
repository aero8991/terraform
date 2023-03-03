import json
import boto3


def lambda_handler(event, context):
    # TODO implement
    print("----------------------------------")
    client = boto3.client('glue')
    client.start_job_run(
        JobName='glue-etl',
        Arguments={}
    )

    return {
        'statusCode': 200,
        'body': json.dumps('Glue job successfully triggered')
    }
