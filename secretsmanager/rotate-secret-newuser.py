import boto3
import json
import logging
import pg
import pgdb
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Secrets Manager RDS PostgreSQL Handler

    This handler uses the single-user rotation scheme to rotate an RDS PostgreSQL user credential. This rotation
    scheme creates a new user on every rotation.
    
    The Secret SecretString is expected to be a JSON string with the following format:
    {
        'engine': <required: must be set to 'postgres'>,
        'host': <required: instance host name>,
        'username': <required: username>,
        'password': <required: password>,
        'dbname': <optional: database name, default to 'postgres'>,
        'port': <optional: if not specified, default port 5432 will be used>,
        'master_arn': <required: ARN of the master secret>
    }

    Args:
        event (dict): Lambda dictionary of event parameters. These keys must include the following:
            - SecretId: The secret ARN or identifier
            - ClientRequestToken: The ClientRequestToken of the secret version
            - Step: The rotation step (one of createSecret, setSecret, testSecret, or finishSecret)

        context (LambdaContext): The Lambda runtime information

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

    """
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    # Setup the client
    service_client = boto3.client('secretsmanager')

    # Make sure the version is staged correctly
    metadata = service_client.describe_secret(SecretId=arn)
    if "RotationEnabled" in metadata and not metadata['RotationEnabled']:
        logger.error("Secret %s is not enabled for rotation" % arn)
        raise ValueError("Secret %s is not enabled for rotation" % arn)
    versions = metadata['VersionIdsToStages']
    if token not in versions:
        logger.error("Secret version %s has no stage for rotation of secret %s." % (token, arn))
        raise ValueError("Secret version %s has no stage for rotation of secret %s." % (token, arn))
    if "AWSCURRENT" in versions[token]:
        logger.info("Secret version %s already set as AWSCURRENT for secret %s." % (token, arn))
        return
    elif "AWSPENDING" not in versions[token]:
        logger.error("Secret version %s not set as AWSPENDING for rotation of secret %s." % (token, arn))
        raise ValueError("Secret version %s not set as AWSPENDING for rotation of secret %s." % (token, arn))

    # Call the appropriate step
    if step == "createSecret":
        create_secret(service_client, arn, token)

    elif step == "setSecret":
        set_secret(service_client, arn, token)

    elif step == "testSecret":
        test_secret(service_client, arn, token)

    elif step == "finishSecret":
        finish_secret(service_client, arn, token)

    else:
        logger.error("lambda_handler: Invalid step parameter %s for secret %s" % (step, arn))
        raise ValueError("Invalid step parameter %s for secret %s" % (step, arn))

def create_secret(service_client, arn, token):
    # Make sure the current secret exists
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")

    # Now try to get the secret version, if that fails, put a new secret
    try:
        get_secret_dict(service_client, arn, "AWSPENDING", token)
        logger.info("createSecret: Successfully retrieved secret for %s." % arn)
    except service_client.exceptions.ResourceNotFoundException:
        # Generate a new secret
        new_username = "user_" + str(uuid.uuid4())[:8]
        new_password = service_client.get_random_password(ExcludeCharacters='/@"\'\\')
        new_password = new_password['RandomPassword']

        # Put the secret
        service_client.put_secret_value(SecretId=arn, ClientRequestToken=token, SecretString=json.dumps({
            'engine': current_dict['engine'],
            'host': current_dict['host'],
            'username': new_username,
            'password': new_password,
            'dbname': current_dict['dbname'],
            'port': current_dict['port'],
            'master_arn': current_dict['master_arn']
        }), VersionStages=['AWSPENDING'])
        logger.info("createSecret: Successfully put secret for ARN %s and version %s." % (arn, token))

def set_secret(service_client, arn, token):
    # Retrieve the master secret
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    master_arn = current_dict['master_arn']
    master_secret = get_secret_dict(service_client, master_arn, "AWSCURRENT")
    
    # Get the pending secret
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)

    # Connect using the master secret
    conn = get_connection(master_secret)

    if not conn:
        logger.error("setSecret: Unable to log into database with the master secret of secret arn %s" % master_arn)
        raise ValueError("Unable to log into database with the master secret of secret arn %s" % master_arn)

    # Now set the pending password and create user if necessary
    try:
        with conn.cursor() as cur:
            # Create new user
            cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (pending_dict['username'],))
            if cur.fetchone() is None:
                cur.execute("CREATE USER %s WITH PASSWORD %s", (pending_dict['username'], pending_dict['password']))
                # Grant necessary permissions here
                cur.execute("GRANT CONNECT ON DATABASE %s TO %s", (master_secret['dbname'], pending_dict['username']))
                # Add more GRANT statements as needed
                logger.info("setSecret: Created new user %s in PostgreSQL DB for secret arn %s." % (pending_dict['username'], arn))
            else:
                cur.execute("ALTER USER %s WITH PASSWORD %s", (pending_dict['username'], pending_dict['password']))
                logger.info("setSecret: Updated password for user %s in PostgreSQL DB for secret arn %s." % (pending_dict['username'], arn))

        conn.commit()
        logger.info("setSecret: Successfully set secret for arn %s." % arn)
    finally:
        conn.close()

def test_secret(service_client, arn, token):
    # Try to login with the pending secret, if it succeeds, return
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)
    conn = get_connection(pending_dict)
    if conn:
        # This is where the lambda will validate the user's permissions. Modify this part to check for
        # your desired permissions.
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT NOW()")
                cur.fetchone()
            logger.info("testSecret: Successfully signed into PostgreSQL DB with AWSPENDING secret in secret arn %s." % arn)
            return
        finally:
            conn.close()

    # If we can't connect with the pending secret, raise a ValueError
    logger.error("testSecret: Unable to log into database with pending secret of secret arn %s" % arn)
    raise ValueError("Unable to log into database with pending secret of secret arn %s" % arn)

def finish_secret(service_client, arn, token):
    # First describe the secret to get the current version
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                # The correct version is already marked as current, return
                logger.info("finishSecret: Version %s already marked as AWSCURRENT for %s" % (version, arn))
                return
            current_version = version
            break

    # Finalize by staging the secret version current
    service_client.update_secret_version_stage(SecretId=arn, VersionStage="AWSCURRENT", MoveToVersionId=token, RemoveFromVersionId=current_version)
    logger.info("finishSecret: Successfully set AWSCURRENT stage to version %s for secret %s." % (token, arn))

    # Deactivate the previous user using master credentials
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    master_arn = current_dict['master_arn']
    master_secret = get_secret_dict(service_client, master_arn, "AWSCURRENT")
    previous_dict = get_secret_dict(service_client, arn, "AWSPREVIOUS")
    
    conn = get_connection(master_secret)
    if conn:
        try:
            with conn.cursor() as cur:
                # Revoke all privileges from the previous user
                cur.execute("REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM %s" % previous_dict['username'])
                # Prevent the user from logging in
                cur.execute("ALTER USER %s WITH NOLOGIN" % previous_dict['username'])
                logger.info("finishSecret: Successfully deactivated previous user %s for secret %s." % (previous_dict['username'], arn))
            conn.commit()
        except Exception as e:
            logger.error("finishSecret: Error deactivating previous user: %s" % str(e))
        finally:
            conn.close()
    else:
        logger.error("finishSecret: Unable to connect to database to deactivate previous user for secret %s" % arn)

def get_connection(secret_dict):
    # Parse and validate the secret JSON string
    port = int(secret_dict['port']) if 'port' in secret_dict else 5432
    dbname = secret_dict['dbname'] if 'dbname' in secret_dict else "postgres"

    # Try to obtain a connection to the db
    try:
        conn = pgdb.connect(host=secret_dict['host'], user=secret_dict['username'], password=secret_dict['password'], database=dbname, port=port, connect_timeout=5)
        return conn
    except pg.InternalError:
        return None

def get_secret_dict(service_client, arn, stage, token=None):
    required_fields = ['host', 'username', 'password', 'master_arn']

    # Only do VersionId validation against the stage if a token is passed in
    if token:
        secret = service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage=stage)
    else:
        secret = service_client.get_secret_value(SecretId=arn, VersionStage=stage)
    plaintext = secret['SecretString']
    secret_dict = json.loads(plaintext)

    # Run validations against the secret
    if 'engine' not in secret_dict or secret_dict['engine'] != 'postgres':
        raise KeyError("Database engine must be set to 'postgres' in secret %s." % arn)
    for field in required_fields:
        if field not in secret_dict:
            raise KeyError("%s key is missing from secret JSON" % field)

    # Parse and return the secret JSON string
    return secret_dict
