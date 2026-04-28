import json
import boto3
import logging
import os
import re
import time
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level, logging.INFO))

# Initialize AWS clients
ec2_client = boto3.client('ec2')
ssm_client = boto3.client('ssm')
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
AUTO_HEALING_ENABLED = os.environ.get('AUTO_HEALING_ENABLED', 'true').lower() == 'true'
HEALING_ACTION_TIMEOUT = int(os.environ.get('HEALING_ACTION_TIMEOUT', 300))
MAX_HEALING_ATTEMPTS = int(os.environ.get('MAX_HEALING_ATTEMPTS', 3))
ENABLE_MULTI_REGION = os.environ.get('ENABLE_MULTI_REGION', 'false').lower() == 'true'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def log_healing_action(instance_id: str, action: str, status: str, details: str = ""):
    """Log healing action for audit trail"""
    timestamp = datetime.utcnow().isoformat()
    log_entry = {
        'timestamp': timestamp,
        'instance_id': instance_id,
        'action': action,
        'status': status,
        'details': details
    }
    logger.info(f"HEALING_ACTION: {json.dumps(log_entry)}")
    return log_entry


def parse_sns_message(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse SNS message from CloudWatch alarm or Nagios alert.
    
    Expected SNS message format:
    {
        "AlarmName": "alarm-name",
        "NewStateValue": "ALARM",
        "AlarmDescription": "...",
        "StateChangeTime": "...",
        "Region": "us-east-1",
        "Trigger": {
            "MetricName": "CPUUtilization",
            "Namespace": "AWS/EC2",
            "Dimensions": {"InstanceId": "i-xxx"}
        }
    }
    """
    try:
        sns_message = event.get('Records', [{}])[0].get('Sns', {})
        message_str = sns_message.get('Message', '{}')
        
        # Try to parse as JSON, handle both JSON and plain text messages
        if isinstance(message_str, str):
            try:
                message = json.loads(message_str)
            except json.JSONDecodeError:
                logger.warning(f"Could not parse as JSON, treating as plain text: {message_str}")
                message = {'raw_message': message_str}
        else:
            message = message_str
            
        logger.info(f"Parsed SNS Message: {json.dumps(message, default=str)}")
        return message
        
    except Exception as e:
        logger.error(f"Error parsing SNS message: {str(e)}", exc_info=True)
        return {}


def extract_instance_id(message: Dict[str, Any]) -> Optional[str]:
    """Extract instance ID from CloudWatch alarm message"""
    # Try different paths where instance ID might be
    paths = [
        ['Trigger', 'Dimensions', 'InstanceId'],
        ['instance_id'],
        ['InstanceId'],
    ]
    
    for path in paths:
        try:
            value = message
            for key in path:
                value = value[key]
            if value and isinstance(value, str) and value.startswith('i-'):
                logger.info(f"Extracted instance ID from path {path}: {value}")
                return value
        except (KeyError, TypeError, IndexError):
            continue
    
    # Try regex extraction from raw message
    if 'raw_message' in message:
        match = re.search(r'(i-[a-z0-9]+)', str(message['raw_message']))
        if match:
            return match.group(1)
    
    logger.warning("Could not extract instance ID from message")
    return None


def get_instance_details(instance_id: str) -> Optional[Dict[str, Any]]:
    """Get EC2 instance details"""
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instances = response['Reservations'][0]['Instances']
        if instances:
            return instances[0]
    except Exception as e:
        logger.error(f"Error getting instance details for {instance_id}: {str(e)}")
    return None


def get_instance_metrics(instance_id: str) -> Dict[str, float]:
    """Get recent CloudWatch metrics for instance"""
    try:
        metrics = {}
        
        # Get CPU utilization
        cpu_response = cloudwatch_client.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=datetime.utcnow() - timedelta(minutes=5),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average']
        )
        if cpu_response['Datapoints']:
            metrics['cpu_utilization'] = cpu_response['Datapoints'][-1]['Average']
        
        logger.info(f"Instance {instance_id} metrics: {metrics}")
        return metrics
        
    except Exception as e:
        logger.error(f"Error getting metrics for {instance_id}: {str(e)}")
        return {}


def determine_healing_action(message: Dict[str, Any], instance_id: str) -> str:
    """
    Determine appropriate healing action based on alarm type and instance state.
    
    Returns: healing_action (reboot, restart_service, clear_cache, etc.)
    """
    alarm_name = message.get('AlarmName', '').lower()
    metric_name = message.get('Trigger', {}).get('MetricName', '').lower()
    
    # Status check failed -> Reboot
    if 'status-check' in alarm_name or 'statuscheckfailed' in metric_name:
        return 'reboot'
    
    # CPU high -> Run optimization script
    if 'cpu' in alarm_name or 'cpuutilization' in metric_name:
        return 'optimize_cpu'
    
    # Memory high -> Clear cache and restart services
    if 'memory' in alarm_name or 'memoryutilization' in metric_name:
        return 'clear_cache'
    
    # Disk high -> Cleanup logs and temp files
    if 'disk' in alarm_name or 'diskutilization' in metric_name:
        return 'cleanup_disk'
    
    # Default action
    return 'diagnostic'


def execute_reboot_instance(instance_id: str) -> bool:
    """Reboot EC2 instance"""
    try:
        if not AUTO_HEALING_ENABLED:
            logger.info(f"Auto-healing disabled, skipping reboot for {instance_id}")
            return False
            
        logger.info(f"Rebooting instance {instance_id}")
        ec2_client.reboot_instances(InstanceIds=[instance_id])
        log_healing_action(instance_id, 'reboot', 'initiated', 'EC2 instance reboot initiated')
        return True
        
    except Exception as e:
        logger.error(f"Error rebooting instance {instance_id}: {str(e)}")
        log_healing_action(instance_id, 'reboot', 'failed', str(e))
        return False


def execute_ssm_command(instance_id: str, action: str) -> bool:
    """Execute healing script on instance via Systems Manager"""
    try:
        if not AUTO_HEALING_ENABLED:
            logger.info(f"Auto-healing disabled, skipping SSM command for {instance_id}")
            return False
        
        # Verify instance is running and has SSM access
        instance = get_instance_details(instance_id)
        if not instance:
            logger.error(f"Instance {instance_id} not found")
            return False
        
        if instance['State']['Name'] != 'running':
            logger.warning(f"Instance {instance_id} is not running, cannot execute SSM command")
            return False
        
        # Build command based on action
        commands = {
            'optimize_cpu': [
                '#!/bin/bash',
                'set -e',
                'echo "Optimizing CPU..."',
                'killall -9 stress 2>/dev/null || true',
                'sync',
            ],
            'clear_cache': [
                '#!/bin/bash',
                'set -e',
                'echo "Clearing caches..."',
                'sync; echo 3 > /proc/sys/vm/drop_caches',
                'systemctl restart httpd || true',
                'systemctl restart nginx || true',
            ],
            'cleanup_disk': [
                '#!/bin/bash',
                'set -e',
                'echo "Cleaning up disk space..."',
                'find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true',
                'rm -rf /tmp/* 2>/dev/null || true',
                'apt-get clean || yum clean all || true',
            ],
            'diagnostic': [
                '#!/bin/bash',
                'echo "Running diagnostics..."',
                'df -h',
                'free -m',
                'ps aux --sort=-%cpu | head -20',
            ]
        }
        
        command = commands.get(action, commands['diagnostic'])
        
        logger.info(f"Executing SSM command: {action} on instance {instance_id}")
        
        response = ssm_client.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'command': command},
            TimeoutSeconds=HEALING_ACTION_TIMEOUT
        )
        
        command_id = response['Command']['CommandId']
        logger.info(f"SSM command {command_id} sent to instance {instance_id}")
        log_healing_action(instance_id, f'ssm_{action}', 'initiated', f'Command ID: {command_id}')
        
        # Check command status
        max_attempts = 10
        for attempt in range(max_attempts):
            time.sleep(3)
            status_response = ssm_client.get_command_invocation(
                CommandId=command_id,
                InstanceId=instance_id
            )
            
            status = status_response['Status']
            logger.info(f"Command {command_id} status: {status}")
            
            if status in ['Success', 'Failed']:
                if status == 'Success':
                    log_healing_action(instance_id, f'ssm_{action}', 'completed', 'SSM command completed successfully')
                    return True
                else:
                    error_msg = status_response.get('StandardErrorContent', 'Unknown error')
                    log_healing_action(instance_id, f'ssm_{action}', 'failed', error_msg)
                    return False
        
        logger.warning(f"Command {command_id} did not complete within timeout period")
        return False
        
    except Exception as e:
        logger.error(f"Error executing SSM command on {instance_id}: {str(e)}")
        log_healing_action(instance_id, f'ssm_{action}', 'failed', str(e))
        return False


def publish_healing_result(instance_id: str, action: str, success: bool, details: str = ""):
    """Publish healing result to SNS for notification"""
    try:
        if not SNS_TOPIC_ARN:
            logger.warning("SNS topic ARN not configured, skipping notification")
            return
        
        message = {
            'healing_action': action,
            'instance_id': instance_id,
            'status': 'success' if success else 'failed',
            'timestamp': datetime.utcnow().isoformat(),
            'details': details
        }
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Auto-Heal: {action} - {instance_id}",
            Message=json.dumps(message, indent=2, default=str)
        )
        
        logger.info(f"Published healing result to SNS: {message}")
        
    except Exception as e:
        logger.error(f"Error publishing to SNS: {str(e)}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Triggered by SNS from CloudWatch alarms or Nagios webhooks.
    Parses alert, determines healing action, and executes remediation.
    """
    
    logger.info(f"Lambda invoked with event: {json.dumps(event, default=str)}")
    
    try:
        # Parse SNS message
        message = parse_sns_message(event)
        
        # Extract instance ID
        instance_id = extract_instance_id(message)
        
        if not instance_id:
            logger.warning("No instance ID found in alert")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Could not extract instance ID from alert'})
            }
        
        logger.info(f"Processing alert for instance: {instance_id}")
        
        # Get instance details
        instance = get_instance_details(instance_id)
        if not instance:
            logger.error(f"Instance {instance_id} not found or inaccessible")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': f'Instance {instance_id} not found'})
            }
        
        logger.info(f"Instance state: {instance['State']['Name']}")
        
        # Determine healing action
        action = determine_healing_action(message, instance_id)
        logger.info(f"Determined healing action: {action}")
        
        # Execute healing action
        success = False
        if action == 'reboot':
            success = execute_reboot_instance(instance_id)
        else:
            success = execute_ssm_command(instance_id, action)
        
        # Publish result
        publish_healing_result(instance_id, action, success, message.get('AlarmDescription', ''))
        
        return {
            'statusCode': 200 if success else 500,
            'body': json.dumps({
                'instance_id': instance_id,
                'action': action,
                'status': 'completed' if success else 'failed',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Unhandled exception in Lambda handler: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Lambda execution failed: {str(e)}'})
        }
