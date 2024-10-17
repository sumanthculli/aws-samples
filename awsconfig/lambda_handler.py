import boto3
import json
import kubernetes
from kubernetes import client, config
from datetime import datetime, timezone

def lambda_handler(event, context):
    # Configure kubernetes client
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    
    # List all namespaces
    namespaces = v1.list_namespace()
    
    certificates = []
    
    for ns in namespaces.items:
        # List certificates in each namespace
        api_instance = client.CustomObjectsApi()
        certs = api_instance.list_namespaced_custom_object(
            group="cert-manager.io",
            version="v1",
            namespace=ns.metadata.name,
            plural="certificates"
        )
        
        for cert in certs['items']:
            cert_data = {
                "Name": cert['metadata']['name'],
                "Namespace": cert['metadata']['namespace'],
                "CommonName": cert['spec'].get('commonName', ''),
                "DNSNames": cert['spec'].get('dnsNames', []),
                "Issuer": cert['spec']['issuerRef']['name'],
                "SecretName": cert['spec']['secretName'],
                "RenewalTime": cert['status'].get('renewalTime', ''),
                "Labels": cert['metadata'].get('labels', {})  # Add this line

            }
            certificates.append(cert_data)
    
    # Create AWS Config configuration items
    config_client = boto3.client('config')
    
    for cert in certificates:
        config_item = {
            'configurationItemStatus': 'OK',
            'resourceType': 'Custom::CertManagerCertificate',
            'resourceId': f"{cert['Namespace']}/{cert['Name']}",
            'resourceName': cert['Name'],
            'ARN': f"arn:aws:eks::{context.invoked_function_arn.split(':')[4]}:certificate/{cert['Namespace']}/{cert['Name']}",
            'configuration': json.dumps(cert),
            'configurationItemCaptureTime': datetime.now(timezone.utc).isoformat()
        }
        
        config_client.put_evaluations(
            Evaluations=[
                {
                    'ComplianceResourceType': 'Custom::CertManagerCertificate',
                    'ComplianceResourceId': f"{cert['Namespace']}/{cert['Name']}",
                    'ComplianceType': 'COMPLIANT',
                    'OrderingTimestamp': datetime.now(timezone.utc)
                }
            ],
            ResultToken=event['resultToken']
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(certificates)} certificates')
    }
