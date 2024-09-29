import boto3
import json
import logging
import os
import pg
import pgdb
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)
MAX_RDS_DB_INSTANCE_ARN_LENGTH = 256


def lambda_handler(event, context):
    """Secrets Manager RDS PostgreSQL Handler

    This handler uses the master-user rotation scheme to rotate an RDS PostgreSQL user credential. This rotation
    scheme creates a new user on every rotation.

    The Secret SecretString is expected to be a JSON string with the following format:
    {
        'engine': <required: must be set to 'postgres'>,
        'host': <required: instance host name>,
        'username': <required: username>,
        'password': <required: password>,
        'dbname': <optional: database name, default to 'postgres'>,
        'port': <optional: if not specified, default to 5432>,
        'masterarn': <required: the arn of the master secret which will be used to create users/change passwords>
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
    service_client = boto3.client('secretsmanager', endpoint_url=os.environ['SECRETS_MANAGER_ENDPOINT'])

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
    """Create the secret

    This method first checks for the existence of a secret for the passed in token. If one does not exist, it will generate a
    new secret and put it with the passed in token.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn does not exist

    """
    # Make sure the current secret exists
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    
    # Now try to get the secret version, if that fails, put a new secret
    try:
        get_secret_dict(service_client, arn, "AWSPENDING", token)
        logger.info("createSecret: Successfully retrieved secret for %s." % arn)
    except service_client.exceptions.ResourceNotFoundException:
        # Generate a new username
        current_dict['username'] = generate_new_username(current_dict['username'])
        current_dict['password'] = get_random_password(service_client)
        
        # Put the secret
        service_client.put_secret_value(SecretId=arn, ClientRequestToken=token, SecretString=json.dumps(current_dict), VersionStages=['AWSPENDING'])
        logger.info("createSecret: Successfully put secret for ARN %s and version %s." % (arn, token))

def set_secret(service_client, arn, token):
    """Set the pending secret in the database

    This method tries to login to the database with the AWSPENDING secret and creates the user if it doesn't exist.
    It then grants all privileges from the current user to the new user.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

    """
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)

    # Use the master arn from the current secret to fetch master secret contents
    master_arn = current_dict['masterarn']
    master_dict = get_secret_dict(service_client, master_arn, "AWSCURRENT", None, True)

    # Fetch dbname from the Child User
    master_dict['dbname'] = current_dict.get('dbname', 'postgres')

    # Now log into the database with the master credentials
    conn = get_connection(master_dict)
    if not conn:
        logger.error("setSecret: Unable to log into database using credentials in master secret %s" % master_arn)
        raise ValueError("Unable to log into database using credentials in master secret %s" % master_arn)

    # Now set the password to the pending password
    try:
        with conn.cursor() as cur:

            # Get escaped usernames via quote_ident
            cur.execute("SELECT quote_ident(%s)", (pending_dict['username'],))
            pending_username = cur.fetchone()[0]
            cur.execute("SELECT quote_ident(%s)", (current_dict['username'],))
            current_username = cur.fetchone()[0]

            # Create the new user
            create_role = "CREATE ROLE %s" % pending_username
            cur.execute(create_role + " WITH LOGIN PASSWORD %s", (pending_dict['password'],))
            
            # Grant permissions from the current user to the new user
            cur.execute("GRANT %s TO %s" % (current_username, pending_username))
            
        conn.commit()
        logger.info("setSecret: Successfully created new user %s and granted permissions." % pending_dict['username'])
    finally:
        conn.close()

def test_secret(service_client, arn, token):
    """Test the pending secret against the database

    This method tries to log into the database with the secrets staged with AWSPENDING and runs
    a permissions check to ensure the user has the correct permissions.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not valid

    """
    # Try to login with the pending secret, if it succeeds, return
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)
    conn = get_connection(pending_dict)
    if conn:
        # This is where the lambda will validate the user's permissions. Modify this part to check for
        # your desired permissions.
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT NOW()")
                conn.commit()
        finally:
            conn.close()
        logger.info("testSecret: Successfully signed into PostgreSQL DB with AWSPENDING secret in %s." % arn)
        return
    else:
        logger.error("testSecret: Unable to log into database with pending secret of secret ARN %s" % arn)
        raise ValueError("Unable to log into database with pending secret of secret ARN %s" % arn)

def finish_secret(service_client, arn, token):
    """Finish the rotation by marking the pending secret as current

    This method finishes the secret rotation by staging the secret staged AWSPENDING with the AWSCURRENT stage.

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version

    """
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

    # Revoke permissions from the old user and optionally delete it
    current_dict = get_secret_dict(service_client, arn, "AWSCURRENT")
    pending_dict = get_secret_dict(service_client, arn, "AWSPENDING", token)

    # Use the master arn from the current secret to fetch master secret contents
    master_arn = current_dict['masterarn']
    master_dict = get_secret_dict(service_client, master_arn, "AWSCURRENT", None, True)

    # Fetch dbname from the Child User
    master_dict['dbname'] = current_dict.get('dbname', 'postgres')

    conn = get_connection(master_dict)
    try:
        with conn.cursor() as cur:
            # Revoke permissions
            cur.execute("REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM %s" % current_dict['username'])
            
            # Optionally, drop the old user 
            #cur.execute("DROP USER IF EXISTS %s" % current_dict['username'])
        
        conn.commit()
        logger.info("finishSecret: Successfully revoked permissions from old user %s and dropped it." % current_dict['username'])
    finally:
        conn.close()

    # Finalize by staging the secret version current
    service_client.update_secret_version_stage(SecretId=arn, VersionStage="AWSCURRENT", MoveToVersionId=token, RemoveFromVersionId=current_version)
    logger.info("finishSecret: Successfully set AWSCURRENT stage to version %s for secret %s." % (token, arn))

def get_connection(secret_dict):
    """Gets a connection to PostgreSQL DB from a secret dictionary

    This helper function tries to connect to the database grabbing connection info
    from the secret dictionary. If successful, it returns the connection, else None

    Args:
        secret_dict (dict): The Secret Dictionary

    Returns:
        Connection: The pgdb.Connection object if successful. None otherwise

    Raises:
        KeyError: If the secret json does not contain the expected keys

    """
    # Parse and validate the secret JSON string
    port = int(secret_dict['port']) if 'port' in secret_dict else 5432
    dbname = secret_dict['dbname'] if 'dbname' in secret_dict else "postgres"

    # Try to obtain a connection to the db

    try:
        conn = pgdb.connect(host=secret_dict['host'], user=secret_dict['username'], password=secret_dict['password'], database=dbname, port=port, connect_timeout=5)
        return conn
    except pg.InternalError:
        return None
    # try:
    #     conn = pg8000.connect(
    #         host=secret_dict['host'],
    #         user=secret_dict['username'],
    #         password=secret_dict['password'],
    #         database=dbname,
    #         port=port,
    #         ssl_context=True
    #     )
    #     return conn
    # except pg8000.Error:
    #     return None

def get_secret_dict(service_client, arn, stage, token=None, master=False):
    """Gets the secret dictionary corresponding for the secret arn, stage, and token

    This helper function gets credentials for the arn and stage passed in and returns the dictionary by parsing the JSON string

    Args:
        service_client (client): The secrets manager service client

        arn (string): The secret ARN or other identifier

        token (string): The ClientRequestToken associated with the secret version, or None if no validation is desired

        stage (string): The stage identifying the secret version

        master (boolean): If this is a master secret

    Returns:
        SecretDictionary: Secret dictionary

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not valid JSON

    """
    required_fields = ['host', 'username', 'password']

    # Only do VersionId validation against the stage if a token is passed in
    if token:
        secret = service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage=stage)
    else:
        secret = service_client.get_secret_value(SecretId=arn, VersionStage=stage)
    plaintext = secret['SecretString']
    secret_dict = json.loads(plaintext)

    # Run validations against the secret
    # if 'engine' not in secret_dict or secret_dict['engine'] != 'postgres':
    #     raise KeyError("Database engine must be set to 'postgres' in secret %s." % arn)
    
    if master and (set(secret_dict.keys()) == set(['username', 'password'])):
        # If this is an RDS-made Master Secret, we can fetch `host` and other connection params
        # from the DescribeDBInstances/DescribeDBClusters RDS API using the DB Instance/Cluster ARN as a filter.
        # The DB Instance/Cluster ARN is fetched from the RDS-made Master Secret's System Tags.
        db_instance_info = fetch_instance_arn_from_system_tags(service_client, arn)
        if len(db_instance_info) != 0:
            secret_dict = get_connection_params_from_rds_api(secret_dict, db_instance_info)
            logger.info("setSecret: Successfully fetched connection params for Master Secret %s from DescribeDBInstances API." % arn)


        # For non-RDS-made Master Secrets that are missing `host`, this will error below when checking for required connection params.
    for field in required_fields:
        if field not in secret_dict:
            raise KeyError("%s key is missing from secret JSON" % field)
        
    supported_engines = ["postgres", "aurora-postgresql"]
    if secret_dict['engine'] not in supported_engines:
        raise KeyError("Database engine must be set to 'postgres' in order to use this rotation lambda")


    # Parse and return the secret JSON string
    return secret_dict

def get_random_password(service_client):
    """Generates a random password

    This helper function generates a random password using AWS Secrets Manager

    Args:
        service_client (client): The secrets manager service client

    Returns:
        string: A randomly generated password

    """
    password_params = {
        'IncludeSpace': False,
        'RequireEachIncludedType': True,
        'PasswordLength': 16
    }
    response = service_client.get_random_password(**password_params)
    return response['RandomPassword']

def generate_new_username(base_username):
    """Generates a new username based on the current timestamp

    This helper function generates a new username by appending the current timestamp to the base username

    Args:
        base_username (string): The base username to use

    Returns:
        string: A new username

    """
    timestamp = int(time.time())
    return f"{base_username}_{timestamp}"


def fetch_instance_arn_from_system_tags(service_client, secret_arn):
    """Fetches DB Instance/Cluster ARN from the given secret's metadata.

    Fetches DB Instance/Cluster ARN from the given secret's metadata.

    Args:
        service_client (client): The secrets manager service client

        secret_arn (String): The secret ARN used in a DescribeSecrets API call to fetch the secret's metadata.

    Returns:
        db_instance_info (dict): The DB Instance/Cluster ARN of the Primary RDS Instance and the tag for the instance

    """
    metadata = service_client.describe_secret(SecretId=secret_arn)

    if 'Tags' not in metadata:
        logger.warning("setSecret: The secret %s is not a service-linked secret, so it does not have a tag aws:rds:primarydbinstancearn or a tag aws:rds:primarydbclusterarn" % secret_arn)
        return {}

    tags = metadata['Tags']

    # Check if DB Instance/Cluster ARN is present in secret Tags
    db_instance_info = {}
    for tag in tags:
        if tag['Key'].lower() == 'aws:rds:primarydbinstancearn' or tag['Key'].lower() == 'aws:rds:primarydbclusterarn':
            db_instance_info['ARN_SYSTEM_TAG'] = tag['Key'].lower()
            db_instance_info['ARN'] = tag['Value']

    # DB Instance/Cluster ARN must be present in secret System Tags to use this work-around
    if len(db_instance_info) == 0:
        logger.warning("setSecret: DB Instance ARN not present in Metadata System Tags for secret %s" % secret_arn)
    elif len(db_instance_info['ARN']) > MAX_RDS_DB_INSTANCE_ARN_LENGTH:
        logger.error("setSecret: %s is not a valid DB Instance ARN. It exceeds the maximum length of %d." % (db_instance_info['ARN'], MAX_RDS_DB_INSTANCE_ARN_LENGTH))
        raise ValueError("%s is not a valid DB Instance ARN. It exceeds the maximum length of %d." % (db_instance_info['ARN'], MAX_RDS_DB_INSTANCE_ARN_LENGTH))

    return db_instance_info


def get_connection_params_from_rds_api(master_dict, master_instance_info):
    """Fetches connection parameters (`host`, `port`, etc.) from the DescribeDBInstances/DescribeDBClusters RDS API using `master_instance_arn` in the master secret metadata as a filter.

    This helper function fetches connection parameters from the DescribeDBInstances/DescribeDBClusters RDS API using `master_instance_arn` in the master secret metadata as a filter.

    Args:
        master_dict (dictionary): The master secret dictionary that will be updated with connection parameters.

        master_instance_info (dict): A dictionary containing an 'ARN' and 'ARN_SYSTEM_TAG' key.
            - The 'ARN_SYSTEM_TAG' value tells us if the DB is an instance or cluster so we know what 'Describe' RDS API to call and how to setup the connection parameters.
            - The 'ARN' value is the DB Instance/Cluster ARN from master secret System Tags that will be used as a filter in DescribeDBInstances/DescribeDBClusters RDS API calls.

    Returns:
        master_dict (dictionary): An updated master secret dictionary that now contains connection parameters such as `host`, `port`, etc.

    Raises:
        Exception: If there is some error/throttling when calling the DescribeDBInstances/DescribeDBClusters RDS API

        ValueError: If the DescribeDBInstances/DescribeDBClusters RDS API Response contains no Instances
    """
    # Setup the client
    rds_client = boto3.client('rds')

    if master_instance_info['ARN_SYSTEM_TAG'] == 'aws:rds:primarydbinstancearn':
        # Call DescribeDBInstances RDS API
        try:
            describe_response = rds_client.describe_db_instances(DBInstanceIdentifier=master_instance_info['ARN'])
        except Exception as err:
            logger.error("setSecret: Encountered API error while fetching connection parameters from DescribeDBInstances RDS API: %s" % err)
            raise Exception("Encountered API error while fetching connection parameters from DescribeDBInstances RDS API: %s" % err)
        # Verify the instance was found
        instances = describe_response['DBInstances']
        if len(instances) == 0:
            logger.error("setSecret: %s is not a valid DB Instance ARN. No Instances found when using DescribeDBInstances RDS API to get connection params." % master_instance_info['ARN'])
            raise ValueError("%s is not a valid DB Instance ARN. No Instances found when using DescribeDBInstances RDS API to get connection params." % master_instance_info['ARN'])

        # put connection parameters in master secret dictionary
        primary_instance = instances[0]
        master_dict['host'] = primary_instance['Endpoint']['Address']
        master_dict['port'] = primary_instance['Endpoint']['Port']
        master_dict['engine'] = primary_instance['Engine']

    elif master_instance_info['ARN_SYSTEM_TAG'] == 'aws:rds:primarydbclusterarn':
        # Call DescribeDBClusters RDS API
        try:
            describe_response = rds_client.describe_db_clusters(DBClusterIdentifier=master_instance_info['ARN'])
        except Exception as err:
            logger.error("setSecret: Encountered API error while fetching connection parameters from DescribeDBClusters RDS API: %s" % err)
            raise Exception("Encountered API error while fetching connection parameters from DescribeDBClusters RDS API: %s" % err)
        # Verify the instance was found
        instances = describe_response['DBClusters']
        if len(instances) == 0:
            logger.error("setSecret: %s is not a valid DB Cluster ARN. No Instances found when using DescribeDBClusters RDS API to get connection params." % master_instance_info['ARN'])
            raise ValueError("%s is not a valid DB Cluster ARN. No Instances found when using DescribeDBClusters RDS API to get connection params." % master_instance_info['ARN'])

        # put connection parameters in master secret dictionary
        primary_instance = instances[0]
        master_dict['host'] = primary_instance['Endpoint']
        master_dict['port'] = primary_instance['Port']
        master_dict['engine'] = primary_instance['Engine']

    return master_dict
