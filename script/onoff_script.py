import logging
import os
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def onoff(event, context):
    session = boto3.Session()
    ec2 = session.client('ec2')
    
    action = event.get('action', 'stop').lower()
    if action not in ['start', 'stop']:
        logger.error(f"Invalid action provided: {action}")
        return {"statusCode": 400, "body": f"Action '{action}' tidak valid. Gunakan 'start' atau 'stop'."}

    instance_state_filter = 'running' if action == 'stop' else 'stopped'
    
    filters = [
        {'Name': 'tag:AutoStop', 'Values': ['True']},
        {'Name': 'tag:Environment', 'Values': ['Development']},
        {'Name': 'instance-state-name', 'Values': [instance_state_filter]}
    ]
    
    instance_ids = []
    
    try:
        logger.info(f"Memulai pencarian EC2 dengan filter: AutoStop=True, Environment=Development dan State={instance_state_filter}")
        
        paginator = ec2.get_paginator('describe_instances')
        page_iterator = paginator.paginate(Filters=filters)
        
        for page in page_iterator:
            for reservation in page['Reservations']:
                for instance in reservation['Instances']:
                    instance_ids.append(instance['InstanceId'])
                    
    except ClientError as e:
        logger.error(f"Gagal melakukan DescribeInstances: {e.response['Error']['Message']}")
        return {"statusCode": 500, "body": "Gagal mengambil data server dari AWS API."}

    if not instance_ids:
        logger.info(f"Tidak ada server dengan tag AutoStop=True dan Environment=Development yang berstatus {instance_state_filter}.")
        return {"statusCode": 200, "body": f"Tidak ada server yang perlu di-{action}."}

    try:
        message = ""
        if action == 'start':
            logger.info(f"Menyalakan server: {instance_ids}")
            ec2.start_instances(InstanceIds=instance_ids)
            message = f"Berhasil mengirim request START ke: {instance_ids}"
            
        elif action == 'stop':
            logger.info(f"Mematikan server: {instance_ids}")
            ec2.stop_instances(InstanceIds=instance_ids)
            message = f"Berhasil mengirim request STOP ke: {instance_ids}"
            
        return {"statusCode": 200, "body": message}
        
    except ClientError as e:
        logger.error(f"Gagal mengeksekusi {action} pada instances {instance_ids}: {e.response['Error']['Message']}")
        return {"statusCode": 500, "body": f"Gagal mengubah state server ke {action}."}