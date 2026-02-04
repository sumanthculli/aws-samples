import json
import sys
import boto3
from datetime import datetime
from typing import Dict, List, Any

print(f"Python version: {sys.version}")
print(f"boto3 version: {boto3.__version__}")

cloudwatch = boto3.client('cloudwatch')


def lambda_handler(event, context):
    """
    Retrieve CloudWatch alarms in ALARM state and their contributors
    Uses describe_alarm_contributors API (requires boto3 >= 1.42.0)
    """
    
    alarm_name_prefix = event.get('alarm_name_prefix', '')
    alarm_names = event.get('alarm_names', [])
    
    try:
        # Verify API is available
        if not hasattr(cloudwatch, 'describe_alarm_contributors'):
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'describe_alarm_contributors not available',
                    'boto3_version': boto3.__version__,
                    'message': 'Please upgrade boto3 layer to version 1.42.0 or higher'
                })
            }
        
        # Get alarms in ALARM state
        alarms = get_alarms_in_alarm_state(alarm_name_prefix, alarm_names)
        
        if not alarms:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No alarms in ALARM state found',
                    'alarm_count': 0,
                    'total_contributors': 0
                })
            }
        
        print(f"Found {len(alarms)} alarms in ALARM state")
        
        # Process each alarm
        results = []
        total_contributors = 0
        
        for alarm in alarms:
            alarm_name = alarm['AlarmName']
            print(f"Processing alarm: {alarm_name}")
            
            # Get contributors for this alarm
            contributors = get_alarm_contributors(alarm_name)
            
            alarm_details = {
                'alarm_name': alarm_name,
                'alarm_arn': alarm['AlarmArn'],
                'namespace': alarm.get('Namespace', 'N/A'),
                'state_value': alarm['StateValue'],
                'state_reason': alarm.get('StateReason', ''),
                'state_updated': alarm['StateUpdatedTimestamp'].isoformat(),
                'threshold': alarm.get('Threshold'),
                'comparison_operator': alarm.get('ComparisonOperator'),
                'contributors': contributors,
                'contributor_count': len(contributors)
            }
            
            results.append(alarm_details)
            total_contributors += len(contributors)
            print(f"Contributors found: {len(contributors)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, indent=2, default=str),
            'alarm_count': len(results),
            'total_contributors': total_contributors,
            'boto3_version': boto3.__version__
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'traceback': traceback.format_exc()
            })
        }


def get_alarms_in_alarm_state(alarm_name_prefix: str = '', 
                               alarm_names: List[str] = None) -> List[Dict]:
    """Retrieve alarms in ALARM state"""
    params = {
        'StateValue': 'ALARM',
        'AlarmTypes': ['MetricAlarm'],
        'MaxRecords': 100
    }
    
    if alarm_name_prefix:
        params['AlarmNamePrefix'] = alarm_name_prefix
    elif alarm_names:
        params['AlarmNames'] = alarm_names
    
    all_alarms = []
    
    while True:
        response = cloudwatch.describe_alarms(**params)
        all_alarms.extend(response.get('MetricAlarms', []))
        
        next_token = response.get('NextToken')
        if not next_token:
            break
        params['NextToken'] = next_token
    
    return all_alarms


def get_alarm_contributors(alarm_name: str) -> List[Dict]:
    """Get contributors for an alarm that are in ALARM state"""
    contributors = []
    next_token = None
    
    try:
        while True:
            params = {'AlarmName': alarm_name}
            
            if next_token:
                params['NextToken'] = next_token
            
            response = cloudwatch.describe_alarm_contributors(**params)
            
            alarm_contributors = response.get('AlarmContributors', [])
            
            # Process each contributor
            for contributor in alarm_contributors:
                contributor_data = {
                    'contributor_id': contributor.get('ContributorId'),
                    'attributes': contributor.get('ContributorAttributes', {}),
                    'state_reason': contributor.get('StateReason', ''),
                    'state_transitioned': contributor.get('StateTransitionedTimestamp').isoformat() 
                        if contributor.get('StateTransitionedTimestamp') else None,
                    'state': 'ALARM'
                }
                
                # Extract common attributes
                attrs = contributor.get('ContributorAttributes', {})
                contributor_data['account_id'] = attrs.get('AccountId') or attrs.get('AWS.AccountId')
                contributor_data['cluster_name'] = attrs.get('ClusterName')
                contributor_data['namespace'] = attrs.get('Namespace')
                contributor_data['full_pod_name'] = attrs.get('FullPodName') or attrs.get('PodName')
                contributor_data['service'] = attrs.get('Service')
                
                contributors.append(contributor_data)
            
            next_token = response.get('NextToken')
            if not next_token:
                break
        
        return contributors
        
    except Exception as e:
        print(f"Error fetching contributors for {alarm_name}: {e}")
        return []
