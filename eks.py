import boto3
import base64
import requests
from eks_token import get_token

# --- CONFIGURE THESE VALUES ---
CLUSTER_NAME = "aexp-v4-cluster"
REGION = "us-west-2"
ROLE_ARN = "arn:aws:iam::<ACCOUNT-ID>:role/eks-lower-role"  # Set to '' if not assuming role
NAMESPACE = "default"   # Change as needed

# --- ASSUME ROLE IF PROVIDED ---
if ROLE_ARN:
    print("Assuming IAM Role:", ROLE_ARN)
    sts = boto3.client('sts', region_name=REGION)
    resp = sts.assume_role(RoleArn=ROLE_ARN, RoleSessionName="EksTokenSession")
    credentials = resp['Credentials']
    aws_access_key_id = credentials['AccessKeyId']
    aws_secret_access_key = credentials['SecretAccessKey']
    aws_session_token = credentials['SessionToken']
    session = boto3.session.Session(
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        aws_session_token=aws_session_token,
        region_name=REGION
    )
else:
    print("Using default AWS credentials")
    session = boto3.session.Session(region_name=REGION)

eks_client = session.client('eks')

# --- FETCH CLUSTER ENDPOINT & CA ---
desc = eks_client.describe_cluster(name=CLUSTER_NAME)
endpoint = desc['cluster']['endpoint']
ca_data = desc['cluster']['certificateAuthority']['data']
ca_cert = base64.b64decode(ca_data)

# --- GENERATE TOKEN (with assume role if used) ---
token_dict = get_token(
    cluster_name=CLUSTER_NAME,
    role_arn=ROLE_ARN if ROLE_ARN else None,
    region_name=REGION
)
token = token_dict['status']['token']

# --- WRITE CA TO DISK TEMPORARILY ---
import tempfile
with tempfile.NamedTemporaryFile(delete=False) as ca_file:
    ca_file.write(ca_cert)
    ca_path = ca_file.name

# --- QUERY NAMESPACES USING DIRECT K8s API ---
api_url = f"{endpoint}/api/v1/namespaces"
headers = {
    "Authorization": f"Bearer {token}"
}

print("Listing all namespaces:")
resp = requests.get(api_url, headers=headers, verify=ca_path)
print(resp.json())

# --- QUERY RESOURCES IN SPECIFIC NAMESPACE (optional/folder access) ---
pods_url = f"{endpoint}/api/v1/namespaces/{NAMESPACE}/pods"
print(f"\nListing pods in namespace {NAMESPACE}:")
pods_resp = requests.get(pods_url, headers=headers, verify=ca_path)
#print(pods_resp.json())

# CLEANUP
import os
os.remove(ca_path)
