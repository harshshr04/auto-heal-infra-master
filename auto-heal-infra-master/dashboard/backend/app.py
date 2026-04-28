#!/usr/bin/env python3
"""Improved backend proxy for the dashboard.

Changes made:
- Use a `use_env` flag instead of storing the literal 'ENV' marker in credentials.
- Provide `get_ec2_client()` and an `/api/instances` endpoint to list running EC2 instances.
- Ensure credential checks correctly detect environment/CLI credentials.

This file is suitable for local development. In production run it behind a proper WSGI server.
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import os
import boto3
import botocore
import requests
from datetime import datetime, timedelta

app = Flask(__name__)
CORS(app)

# Global credentials storage (in-memory for session)
aws_credentials = {
    'access_key': None,
    'secret_key': None,
    'account_id': None,
    'region': None,
    'use_env': False
}

# Basic config exposed to the frontend (non-sensitive)
FRONTEND_CONFIG = {
    'refreshInterval': 30000,
}


@app.route('/api/login', methods=['POST'])
def aws_login():
    """Login with explicit AWS credentials provided by the frontend."""
    data = request.json or {}
    access_key = data.get('accessKey')
    secret_key = data.get('secretKey')
    region = data.get('region', 'us-east-1')
    if not access_key or not secret_key:
        return jsonify({'error': 'Access Key and Secret Key are required'}), 400
    try:
        sts = boto3.client('sts', aws_access_key_id=access_key, aws_secret_access_key=secret_key, region_name=region)
        idt = sts.get_caller_identity()
        aws_credentials['access_key'] = access_key
        aws_credentials['secret_key'] = secret_key
        aws_credentials['account_id'] = idt['Account']
        aws_credentials['region'] = region
        aws_credentials['use_env'] = False
        return jsonify({'success': True, 'accountId': idt['Account'], 'region': region})
    except botocore.exceptions.ClientError as e:
        return jsonify({'error': str(e)}), 401
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/login/env', methods=['POST'])
def aws_login_env():
    """Mark that the app should use the default AWS credential chain (env/CLI/instance role).

    This endpoint performs a quick STS call to validate credentials are available.
    """
    region = (request.json or {}).get('region', 'us-east-1')
    try:
        sts = boto3.client('sts', region_name=region)
        idt = sts.get_caller_identity()
        # Do not set access/secret keys when using env; instead set the `use_env` flag.
        aws_credentials['access_key'] = None
        aws_credentials['secret_key'] = None
        aws_credentials['account_id'] = idt['Account']
        aws_credentials['region'] = region
        aws_credentials['use_env'] = True
        return jsonify({'success': True, 'accountId': idt['Account'], 'region': region})
    except botocore.exceptions.NoCredentialsError:
        return jsonify({'error': 'No credentials found'}), 401
    except botocore.exceptions.ClientError as e:
        # Surface helpful messages for common auth failures
        code = e.response.get('Error', {}).get('Code', '')
        if code == 'InvalidClientTokenId':
            return jsonify({'error': 'Invalid/expired credentials in environment'}), 401
        return jsonify({'error': str(e)}), 401
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/logout', methods=['POST'])
def aws_logout():
    aws_credentials.update({'access_key': None, 'secret_key': None, 'account_id': None, 'region': None, 'use_env': False})
    return jsonify({'success': True})


@app.route('/api/auth-status')
def auth_status():
    ok = bool(aws_credentials.get('use_env') or (aws_credentials.get('access_key') is not None))
    return jsonify({'authenticated': ok, 'accountId': aws_credentials.get('account_id'), 'region': aws_credentials.get('region')})


def aws_creds_present():
    """Return True if credentials are present either by env/instance role or manual login."""
    if aws_credentials.get('use_env'):
        return True
    if aws_credentials.get('access_key') and aws_credentials.get('secret_key'):
        return True
    # lastly, check environment variables
    return bool(os.environ.get('AWS_ACCESS_KEY_ID') and os.environ.get('AWS_SECRET_ACCESS_KEY'))


def get_cloudwatch_client():
    if aws_credentials.get('use_env'):
        return boto3.client('cloudwatch', region_name=aws_credentials.get('region') or 'us-east-1')
    if aws_credentials.get('access_key') and aws_credentials.get('secret_key'):
        return boto3.client('cloudwatch', aws_access_key_id=aws_credentials['access_key'], aws_secret_access_key=aws_credentials['secret_key'], region_name=aws_credentials.get('region') or 'us-east-1')
    return boto3.client('cloudwatch')


def get_ec2_client():
    """Get EC2 client with appropriate credentials"""
    if aws_credentials.get('use_env'):
        return boto3.client('ec2', region_name=aws_credentials.get('region') or 'us-east-1')
    if aws_credentials.get('access_key') and aws_credentials.get('secret_key'):
        return boto3.client('ec2', aws_access_key_id=aws_credentials['access_key'], aws_secret_access_key=aws_credentials['secret_key'], region_name=aws_credentials.get('region') or 'us-east-1')
    return boto3.client('ec2')


@app.route('/api/instances')
def instances():
    """Return a list of running EC2 instances visible to the current credentials."""
    if not aws_creds_present():
        return jsonify({'ok': False, 'message': 'AWS credentials not found. Please login first.'}), 401
    try:
        ec2 = get_ec2_client()
        resp = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        out = []
        for r in resp.get('Reservations', []):
            for i in r.get('Instances', []):
                # Extract Name tag if present
                name_tag = ''
                for tag in i.get('Tags', []):
                    if tag.get('Key') == 'Name':
                        name_tag = tag.get('Value', '')
                        break
                
                out.append({
                    'InstanceId': i.get('InstanceId'),
                    'Name': name_tag,
                    'State': i.get('State', {}).get('Name'),
                    'InstanceType': i.get('InstanceType'),
                    'PrivateIpAddress': i.get('PrivateIpAddress'),
                    'PublicIpAddress': i.get('PublicIpAddress'),
                    'LaunchTime': i.get('LaunchTime').isoformat() if i.get('LaunchTime') else None,
                    'Tags': i.get('Tags', [])
                })
        return jsonify({'ok': True, 'instances': out})
    except Exception as e:
        app.logger.exception('Failed to list instances')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/config')
def config():
    cfg = FRONTEND_CONFIG.copy()
    cfg['awsAccountId'] = aws_credentials.get('account_id') or os.environ.get('AWS_ACCOUNT_ID', '')
    cfg['region'] = aws_credentials.get('region') or os.environ.get('AWS_REGION', os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'))
    cfg['nagiosUrl'] = os.environ.get('NAGIOS_URL', '')
    cfg['grafanaUrl'] = os.environ.get('GRAFANA_URL', '')
    cfg['nagiosInstanceId'] = os.environ.get('NAGIOS_INSTANCE_ID', '')
    cfg['grafanaInstanceId'] = os.environ.get('GRAFANA_INSTANCE_ID', '')
    return jsonify(cfg)


@app.route('/api/metrics')
def metrics():
    if not aws_creds_present():
        return jsonify({
            'ok': False,
            'message': 'AWS credentials not found. Please login with your AWS credentials.',
            'mock': True,
            'data': {
                'cpu': 0.0,
                'memory': 0.0,
                'disk': 0.0,
                'lambda_invocations': 0,
                'lambda_duration': 0,
                'lambda_errors': 0,
                'sns_messages': 0,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'activities': [
                    {'type': 'info', 'message': 'No AWS credentials configured - showing placeholder data', 'time': 'Now'}
                ]
            }
        })

    cw = get_cloudwatch_client()

    def recent_stat(namespace, metric_name, dimension_filters=None):
        try:
            now = datetime.utcnow()
            start = now - timedelta(minutes=10)
            params = dict(Namespace=namespace, MetricName=metric_name, StartTime=start, EndTime=now, Period=300, Statistics=['Average'])
            if dimension_filters:
                params['Dimensions'] = dimension_filters
            resp = cw.get_metric_statistics(**params)
            datapoints = resp.get('Datapoints', [])
            if not datapoints:
                return None
            latest = max(datapoints, key=lambda d: d['Timestamp'])
            return latest.get('Average')
        except botocore.exceptions.ClientError as e:
            app.logger.warning('CloudWatch error: %s', e)
            return None

    cpu = recent_stat('AWS/EC2', 'CPUUtilization') or 0.0
    mem = recent_stat('System/Linux', 'MemoryUtilization') or 0.0
    disk = recent_stat('System/Linux', 'DiskSpaceUtilization') or 0.0

    payload = {
        'ok': True,
        'mock': False,
        'data': {
            'cpu': round(cpu, 2),
            'memory': round(mem, 2),
            'disk': round(disk, 2),
            'lambda_invocations': int(recent_stat('AWS/Lambda', 'Invocations') or 0),
            'lambda_duration': int(recent_stat('AWS/Lambda', 'Duration') or 0),
            'lambda_errors': int(recent_stat('AWS/Lambda', 'Errors') or 0),
            'sns_messages': 0,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'activities': []
        }
    }
    return jsonify(payload)


@app.route('/api/nagios')
def nagios():
    nagios_url = os.environ.get('NAGIOS_URL')
    if not nagios_url:
        return jsonify({'ok': False, 'message': 'NAGIOS_URL not configured on server.'}), 400
    path = request.args.get('path', '')
    if not path:
        return jsonify({'ok': False, 'message': 'missing path parameter'}), 400
    user = os.environ.get('NAGIOS_USER')
    pwd = os.environ.get('NAGIOS_PASS')
    full = nagios_url.rstrip('/') + '/' + path.lstrip('/')
    try:
        if user and pwd:
            r = requests.get(full, auth=(user, pwd), timeout=10)
        else:
            r = requests.get(full, timeout=10)
        return (r.content, r.status_code, {'Content-Type': r.headers.get('Content-Type', 'application/json')})
    except requests.RequestException as e:
        app.logger.warning('Nagios proxy error: %s', e)
        return jsonify({'ok': False, 'message': 'failed to fetch from Nagios', 'detail': str(e)}), 502


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '5001')))
