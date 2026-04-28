# Production Deployment Guide

This guide covers deploying the Auto-Heal Dashboard to production on your Grafana server.

## Overview

The system consists of:
1. **Frontend**: HTML/CSS/JS dashboard served by nginx
2. **Backend**: Flask API (gunicorn + systemd)
3. **Monitoring**: Real-time metrics from CloudWatch, Nagios, Lambda

## Pre-Deployment Checklist

### AWS & IAM Setup
- [ ] Create IAM user for dashboard backend (or use instance role)
  - Required permissions: `cloudwatch:GetMetricStatistics`, `cloudwatch:DescribeAlarms`
  - See `iam-policy.json` below for full policy
- [ ] Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
- [ ] Confirm AWS account ID (12 digits)
- [ ] Confirm AWS region (e.g., us-east-1)

### Nagios Setup
- [ ] Confirm Nagios URL is accessible from backend server
- [ ] Create Nagios API user (if using authentication)
- [ ] Confirm JSON API is enabled (`/cgi-bin/statusjson.cgi`)
- [ ] Test manual curl to confirm connectivity

### Grafana Setup
- [ ] Confirm Grafana URL is accessible from dashboard
- [ ] (Optional) Generate Grafana API token for advanced integrations

### Target Server Setup
- [ ] SSH access to Grafana server (ec2-user@3.222.48.52)
- [ ] Sudo/root access for systemd service setup
- [ ] Python 3.6+ installed
- [ ] nginx or Apache running (for static files)

## Deployment Steps

### Step 1: Create IAM User (if needed)

If you don't have an IAM user yet, create one in AWS Console:

```bash
# Via AWS CLI
aws iam create-user --user-name dashboard-backend
aws iam put-user-policy --user-name dashboard-backend --policy-name dashboard --policy-document file://iam-policy.json
aws iam create-access-key --user-name dashboard-backend
```

Save the **Access Key ID** and **Secret Access Key**.

### Step 2: Prepare Environment File

On your **local machine**, create `dashboard/backend/.env`:

```bash
cd dashboard/backend
cp .env.example .env
# Edit .env:
nano .env
```

Fill in your values:

```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
NAGIOS_URL=http://3.219.108.146/nagios
NAGIOS_USER=nagiosadmin
NAGIOS_PASS=...
GRAFANA_URL=http://3.222.48.52:3000
```

**Do not commit .env to git!**

### Step 3: Run Setup Script

```bash
cd /Users/kumarmangalam/Desktop/Devops/auto-heal-infra
./setup_dashboard.sh
```

This will:
1. Copy dashboard HTML to Grafana server
2. Copy backend Python code
3. Create venv and install dependencies
4. Create systemd service (`autoheal-backend.service`)
5. Start the service automatically

### Step 4: Configure Environment on Server

SSH to Grafana server and set up the `.env` file:

```bash
ssh ec2-user@3.222.48.52

# Edit environment file for systemd service
sudo nano /etc/systemd/system/autoheal-backend.service

# Find the [Service] section, add:
#   EnvironmentFile=/opt/auto-heal-dashboard/backend/.env
# Or inline:
#   Environment="AWS_ACCESS_KEY_ID=..."
#   Environment="AWS_SECRET_ACCESS_KEY=..."

sudo systemctl daemon-reload
sudo systemctl restart autoheal-backend
```

Alternatively, store in `/opt/auto-heal-dashboard/backend/.env`:

```bash
sudo tee /opt/auto-heal-dashboard/backend/.env > /dev/null <<EOF
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_ACCOUNT_ID=123456789012
AWS_REGION=us-east-1
NAGIOS_URL=http://3.219.108.146/nagios
NAGIOS_USER=nagiosadmin
NAGIOS_PASS=...
GRAFANA_URL=http://3.222.48.52:3000
EOF

sudo chown ec2-user:ec2-user /opt/auto-heal-dashboard/backend/.env
sudo chmod 600 /opt/auto-heal-dashboard/backend/.env
```

Then update systemd service to load it:

```bash
sudo nano /etc/systemd/system/autoheal-backend.service
# Add under [Service]:
# EnvironmentFile=/opt/auto-heal-dashboard/backend/.env
```

### Step 5: Configure Nginx Reverse Proxy (Optional)

For production HTTPS and reverse proxy, create `/etc/nginx/sites-available/auto-heal-dashboard`:

```nginx
upstream autoheal_backend {
    server 127.0.0.1:5000;
}

server {
    listen 80;
    server_name your-domain.com;
    
    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    client_max_body_size 10M;
    
    # Dashboard frontend
    location / {
        root /var/www/html/auto-heal-dashboard;
        try_files $uri $uri/ =404;
        add_header Cache-Control "public, max-age=3600";
    }
    
    # Backend API proxy
    location /api/ {
        proxy_pass http://autoheal_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Enable and test:

```bash
sudo ln -s /etc/nginx/sites-available/auto-heal-dashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Step 6: Verify Deployment

Check backend service:

```bash
ssh ec2-user@3.222.48.52
sudo systemctl status autoheal-backend
sudo journalctl -u autoheal-backend -n 20

# Test endpoints
curl http://127.0.0.1:5000/api/config
curl http://127.0.0.1:5000/api/metrics
```

Check frontend:

```bash
# Direct access
curl http://3.222.48.52/custom-integrated-dashboard.html | head -20

# Or via nginx (if set up)
curl https://your-domain.com/custom-integrated-dashboard.html | head -20
```

Open in browser:

- Direct: http://3.222.48.52/custom-integrated-dashboard.html
- Via nginx: https://your-domain.com
- Check browser console (F12) for any errors

## IAM Policy

Save as `iam-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:ListFunctions",
        "lambda:GetFunction"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:ListTopics",
        "sns:GetTopicAttributes"
      ],
      "Resource": "*"
    }
  ]
}
```

## Troubleshooting

### Dashboard won't load

1. Check nginx error log: `sudo tail -f /var/log/nginx/error.log`
2. Check file permissions: `ls -la /var/www/html/auto-heal-dashboard/`
3. Check browser console (F12) for CORS or network errors

### Backend API returns errors

1. Check systemd service: `sudo systemctl status autoheal-backend`
2. Check service logs: `sudo journalctl -u autoheal-backend -f`
3. Check AWS credentials: `echo $AWS_ACCESS_KEY_ID`
4. Test manually: `curl http://127.0.0.1:5000/api/config`

### Metrics show as 0 or mock data

1. Ensure AWS credentials are valid
2. Ensure EC2 instances have CloudWatch agent running
3. Ensure instances have proper IAM role for CloudWatch
4. Check backend logs for AWS API errors

### Nagios integration not working

1. Verify Nagios URL is accessible: `curl $NAGIOS_URL`
2. Check authentication: `curl -u nagiosadmin:password $NAGIOS_URL`
3. Verify JSON API endpoint: `curl $NAGIOS_URL/cgi-bin/statusjson.cgi?query=servicelist`
4. Check backend logs for proxy errors

## Monitoring Dashboard Health

### Manual checks

```bash
# Check backend process
ps aux | grep gunicorn

# Check port 5000 listening
lsof -i :5000

# Check service status
sudo systemctl status autoheal-backend

# View recent logs
sudo journalctl -u autoheal-backend -n 50

# Test API responses
curl -w "\n%{http_code}\n" http://127.0.0.1:5000/api/config
curl -w "\n%{http_code}\n" http://127.0.0.1:5000/api/metrics
```

### Set up health check alert (optional)

Create `/usr/local/bin/check-dashboard.sh`:

```bash
#!/bin/bash
RESPONSE=$(curl -s -w "%{http_code}" http://127.0.0.1:5000/api/metrics -o /dev/null)
if [ "$RESPONSE" != "200" ]; then
  echo "Dashboard backend health check failed: $RESPONSE"
  sudo systemctl restart autoheal-backend
fi
```

Add to crontab:

```bash
*/5 * * * * /usr/local/bin/check-dashboard.sh
```

## Rollback / Uninstall

```bash
# Stop service
sudo systemctl stop autoheal-backend
sudo systemctl disable autoheal-backend

# Remove service
sudo rm /etc/systemd/system/autoheal-backend.service
sudo systemctl daemon-reload

# Remove files
sudo rm -rf /opt/auto-heal-dashboard
sudo rm -rf /var/www/html/auto-heal-dashboard

# Reload nginx
sudo systemctl reload nginx
```

## Performance Tuning

### Backend workers

Edit `/etc/systemd/system/autoheal-backend.service`:

```bash
ExecStart=/opt/auto-heal-dashboard/backend/.venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 app:app
```

Recommendation: workers = (2 × CPU_cores) + 1

### Caching

Add to dashboard HTML or nginx:

```nginx
add_header Cache-Control "public, max-age=300";  # 5 min cache
```

### Rate limiting

Add to nginx to prevent abuse:

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

location /api/ {
    limit_req zone=api burst=20 nodelay;
    # ... proxy settings
}
```

## Next Steps

1. [ ] Complete pre-deployment checklist
2. [ ] Create IAM user and get credentials
3. [ ] Prepare `.env` file
4. [ ] Run `setup_dashboard.sh`
5. [ ] Configure environment on server
6. [ ] (Optional) Set up nginx reverse proxy
7. [ ] Verify all endpoints working
8. [ ] Test dashboard in browser
9. [ ] Share URL with team
10. [ ] Set up monitoring/alerts

## Support

For issues or questions:
- Check `backend/README.md` for API docs
- Check `DASHBOARD_GUIDE.md` for frontend features
- Check systemd logs: `journalctl -u autoheal-backend`
