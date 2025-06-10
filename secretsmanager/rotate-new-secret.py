import logging
import json
import boto3
import sys
import psycopg2  # Example for PostgreSQL; change to your DB driver as needed
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_secret_dict(service_client, arn, stage, token=None):
    """Retrieve the secret dictionary for a given stage."""
    required_fields = ['host', 'port', 'dbname', 'username', 'password']
    try:
        secret_value = service_client.get_secret_value(
            SecretId=arn,
            VersionId=token if token else None,
            VersionStage=stage
        ) if token or stage != 'AWSCURRENT' else service_client.get_secret_value(SecretId=arn)
        secret = json.loads(secret_value['SecretString'])
        for field in required_fields:
            if field not in secret:
                raise KeyError(f"{field} not present in secret")
        return secret
    except Exception as e:
        logger.error(f"get_secret_dict: Failed to get secret for {arn} at stage {stage}: {str(e)}")
        raise

def get_connection(secret_dict):
    """Establish a database connection using the secret dictionary."""
    try:
        conn = psycopg2.connect(
            host=secret_dict['host'],
            port=secret_dict['port'],
            dbname=secret_dict['dbname'],
            user=secret_dict['username'],
            password=secret_dict['password']
        )
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        return conn
    except Exception as e:
        logger.error(f"get_connection: Failed to connect to database: {str(e)}")
        raise

def create_user(conn, username, password, privileges='LOGIN'):
    """Create a new database user."""
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_user WHERE usename = %s", (username,))
        if cur.fetchone():
            logger.info(f"User {username} already exists")
            return
        cur.execute(f"CREATE USER {username} WITH PASSWORD %s {privileges}", (password,))
        logger.info(f"Created user {username}")

def drop_user(conn, username):
    """Drop a database user, ignoring if they don't exist."""
    try:
        with conn.cursor() as cur:
            cur.execute("DROP USER IF EXISTS %s", (username,))
            logger.info(f"Dropped user {username}")
    except Exception as e:
        logger.error(f"Failed to drop user {username}: {str(e)}")
        if "does not exist" in str(e).lower() or "user doesn't exist" in str(e).lower():
            logger.info(f"User {username} did not exist, skipping")
        else:
            raise

def set_secret(service_client, arn, token, rotation_token):
    """Set the secret for rotation."""
    try:
        pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)
        # Try to connect with pending credentials to check if user already exists
        try:
            conn = get_connection(pending_dict)
            conn.close()
            logger.info("setSecret: AWSPENDING credentials already valid in database")
            return
        except Exception:
            # User does not exist or credentials are invalid; proceed to create user
            current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
            with get_connection(current_dict) as conn:
                create_user(conn, pending_dict['username'], pending_dict['password'])
    except Exception as e:
        logger.error(f"setSecret: Failed to set secret: {str(e)}")
        raise

def test_secret(service_client, arn, token):
    """Test both current and pending credentials."""
    for stage in ['AWSCURRENT', 'AWSPENDING']:
        try:
            secret_dict = get_secret_dict(service_client, arn, stage)
            with get_connection(secret_dict) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    logger.info(f"testSecret: Successfully tested {stage} credentials")
        except Exception as e:
            logger.error(f"testSecret: Failed testing {stage} credentials: {str(e)}")
            # For application fallback, this should be handled in your app code
            raise

def finish_secret(service_client, arn, token):
    """Finish the rotation by promoting the pending secret and cleaning up."""
    # Get the previous and current secrets
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)
    # Get previous username (assuming it's stored somewhere; adjust as needed)
    # In practice, you might need to track the previous username in a separate field or step
    # Here, we assume the previous username is stored in the secret or can be derived
    previous_username = current_dict['username']
    # Promote pending to current
    service_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=service_client.describe_secret(SecretId=arn)['VersionIdsToStages'][arn][0]
    )
    # Remove previous user
    try:
        with get_connection(pending_dict) as conn:
            drop_user(conn, previous_username)
    except Exception as e:
        logger.error(f"finishSecret: Failed to drop previous user: {str(e)}")
        # If the user doesn't exist, log and continue
        if "does not exist" in str(e).lower() or "user doesn't exist" in str(e).lower():
            logger.info("User already removed")
        else:
            raise

def lambda_handler(event, context):
    """Lambda handler for secret rotation."""
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    rotation_token = event.get('RotationToken', None)  # For cross-account rotation support

    service_client = boto3.client('secretsmanager', endpoint_url="https://secretsmanager.us-east-1.amazonaws.com")
    # Adjust region as needed

    try:
        if step == "createSecret":
            # For createSecret step, you might generate a new password and put it in AWSPENDING
            # This is usually handled by Secrets Manager natively; implement if required
            pass
        elif step == "setSecret":
            set_secret(service_client, arn, token, rotation_token)
        elif step == "testSecret":
            test_secret(service_client, arn, token)
        elif step == "finishSecret":
            finish_secret(service_client, arn, token)
        else:
            logger.error("lambda_handler: Invalid step parameter")
            raise ValueError("Invalid step parameter")
    except Exception as e:
        logger.error(f"lambda_handler: Error during rotation step {step}: {str(e)}")
        raise
