# Auto-Heal Dashboard Backend

This small Flask backend proxies CloudWatch and Nagios queries for the frontend dashboard.

## Features

- `GET /api/config` → Returns AWS account ID, region, dashboard URLs
- `GET /api/metrics` → CloudWatch metrics (CPU, Memory, Disk, Lambda, SNS)
- `GET /api/nagios?path=...` → Proxy Nagios JSON API queries
- Graceful fallback to mock data if AWS credentials not set
- Production-ready (gunicorn/systemd)

## Environment Setup

Copy `.env.example` to `.env` and fill with your values:

```bash
cp .env.example .env
# Edit .env with your AWS credentials and service URLs
```

Environment variables:

- `AWS_ACCESS_KEY_ID` – AWS IAM user access key
- `AWS_SECRET_ACCESS_KEY` – AWS IAM user secret key
- `AWS_ACCOUNT_ID` – AWS account ID (12 digits, used for display)
- `AWS_REGION` – AWS region (default: us-east-1)
- `NAGIOS_URL` – Base URL of Nagios (e.g., http://3.219.108.146/nagios)
- `NAGIOS_INSTANCE_ID` – Nagios EC2 instance ID (e.g., i-0fa823ceb3eeeea4a)
- `NAGIOS_USER` – Nagios API username (optional)
- `NAGIOS_PASS` – Nagios API password (optional)
- `GRAFANA_URL` – Grafana URL (e.g., http://3.222.48.52:3000)
- `GRAFANA_INSTANCE_ID` – Grafana EC2 instance ID (e.g., i-01eb8b49d6572c1ff)
- `PORT` – Server port (default: 5000)
- `FLASK_ENV` – Flask environment (production/development)

Quick local run (development):

```bash
cd dashboard/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt

# Load environment
export $(cat .env | xargs)

# Development server
flask run --host=0.0.0.0 --port=5000

# Or production server (gunicorn)
gunicorn -w 3 -b 0.0.0.0:5000 app:app
```

## Production Deployment

The `setup_dashboard.sh` script:
1. Creates `/opt/auto-heal-dashboard/backend`
2. Sets up a Python venv
3. Installs dependencies
4. Creates a systemd service
5. Auto-starts on boot

To manage service on production:

```bash
sudo systemctl start autoheal-backend
sudo systemctl stop autoheal-backend
sudo systemctl restart autoheal-backend
sudo journalctl -u autoheal-backend -f
```

## Security Notes

- Run behind a reverse proxy (nginx) and enable HTTPS.
- Use systemd environment file or AWS Secrets Manager.
- Never commit `.env` with real credentials to version control.
- Restrict API access to internal network.
- Use IAM roles instead of long-term credentials when possible.
- Rotate credentials regularly.
