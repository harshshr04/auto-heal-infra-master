# 🚀 Complete Grafana & CloudWatch Integration Guide

## Overview
This guide provides step-by-step instructions to set up an integrated Grafana dashboard with CloudWatch for your Auto-Heal Infrastructure.

---

## 📋 Prerequisites

✓ Grafana instance running at: **http://3.222.48.52:3000**  
✓ Default credentials: **admin / admin** (⚠️ Change immediately)  
✓ AWS credentials configured with CloudWatch access  
✓ Auto-Heal Infrastructure deployed  

---

## 🔧 STEP 1: Access Grafana

### Option A: Direct Access
1. Open browser and navigate to: **http://3.222.48.52:3000**
2. Login with credentials:
   - **Username:** admin
   - **Password:** admin

### Option B: SSH Port Forward (Secure)
```bash
ssh -i your-key.pem ec2-user@3.222.48.52 -L 3000:localhost:3000
# Then access http://localhost:3000
```

---

## 🔑 STEP 2: Change Default Password (CRITICAL!)

⚠️ **DO THIS FIRST!**

1. Click on user icon (bottom left) → **Preferences**
2. Click **Change Password**
3. Enter:
   - **Old Password:** admin
   - **New Password:** [Strong password]
   - **Confirm Password:** [Confirm]
4. Click **Change Password**
5. Re-login with new credentials

---

## 📊 STEP 3: Add CloudWatch Data Source

### Automatic Method (Recommended)

```bash
cd /Users/kumarmangalam/Desktop/Devops/auto-heal-infra

# Wait 2-3 minutes for Grafana to fully start, then run:
./setup_grafana.sh http://3.222.48.52:3000 "" us-east-1
```

### Manual Method

1. **Go to Data Sources:**
   - Click **Configuration** (gear icon) → **Data Sources**
   - Click **Add data source**

2. **Select CloudWatch:**
   - Search for "CloudWatch"
   - Click **CloudWatch** option
   - Click **Select**

3. **Configure CloudWatch:**
   - **Name:** CloudWatch
   - **Default Region:** us-east-1
   - **Authentication Provider:** default
   - Leave AWS Credentials as default (IAM role will be used)

4. **Save & Test:**
   - Click **Save & test**
   - You should see: ✓ "Successfully queried the CloudWatch API"

---

## 📈 STEP 4: Import Pre-Built Dashboard

### Method 1: Upload Dashboard JSON

1. **Go to Dashboards:**
   - Click **Dashboards** (dashboard icon) in left sidebar
   - Click **+ New Dashboard** → **Import dashboard**

2. **Upload Dashboard:**
   - Click **Upload JSON file**
   - Select: `/Users/kumarmangalam/Desktop/Devops/auto-heal-infra/grafana_dashboard.json`
   - Click **Load**

3. **Configure:**
   - **Folder:** General
   - **Unique identifier (uid):** auto-heal-dashboard
   - Click **Import**

### Method 2: Paste JSON

1. Go to **Dashboards** → **Import dashboard**
2. Paste the JSON content from `grafana_dashboard.json`
3. Click **Load** → **Import**

---

## 🎯 STEP 5: Dashboard Panels Overview

Your integrated dashboard includes these panels:

### 1. **EC2 CPU Utilization** (Top Left)
- Shows CPU usage across all target instances
- 60-80% = Yellow warning
- >80% = Red alert
- Triggers healing function if threshold exceeded

### 2. **Memory & Disk Utilization** (Top Right)
- Custom CloudWatch metrics from the CloudWatch agent
- 70-85% = Yellow warning
- >85% = Red alert
- Auto-healing clears cache if threshold hit

### 3. **Lambda Healing Function Activity** (Middle Left)
- Shows how many times healing function was invoked
- Displays error count in red
- Indicates healing effectiveness

### 4. **Lambda Execution Duration** (Middle Center)
- Average and max execution time in milliseconds
- Helps identify performance issues
- Yellow: 30-50 seconds, Red: >50 seconds

### 5. **SNS Alerts Published** (Middle Right)
- Number of alerts sent to SNS topic
- Correlates with healing events
- Shows alert volume over time

### 6. **EC2 Instance Health Status** (Bottom Left)
- Real-time health check results
- Green = ✅ Healthy
- Red = ❌ Failed
- Automatic instance healing triggered on failure

### 7. **CloudWatch Alarms Status** (Bottom Right)
- Displays active alarm triggers
- Shows which thresholds are being exceeded
- Links to CloudWatch console

---

## ⚙️ STEP 6: Configure Variables & Filters

### Instance Filter

1. **At the top of dashboard, find "Instance" dropdown**
2. Select instances to monitor:
   - "All" = Monitor all instances
   - Individual instance IDs = Specific instance

3. **Auto-Apply Time Range:**
   - Click **Last 1 hour** (top right)
   - Choose: 5m, 15m, 1h, 6h, 24h, 7d, 30d

4. **Auto-Refresh:**
   - Click refresh icon (top right)
   - Choose: 30s, 1m, 5m, etc.

---

## 📊 STEP 7: Real-Time Monitoring

### Watch for Healing Events

1. **Lambda Activity Panel:**
   - Look for invocation spikes
   - Check for red errors
   - Count total invocations

2. **SNS Alerts Panel:**
   - Correlate with Lambda invocations
   - More alerts = more problems detected

3. **EC2 Health Status:**
   - Green = All instances healthy
   - Red bars = Failed health checks
   - Auto-healing triggers on failures

4. **CPU & Memory Trends:**
   - Watch for upward trends
   - Set custom alerts if needed

---

## 🔔 STEP 8: Create Custom Alerts (Optional)

### Add Alert to CPU Panel

1. **Edit dashboard:** Click **Edit dashboard** button (top right)

2. **Select CPU Utilization panel** → Click **Edit** (pencil icon)

3. **Go to Alert tab:**
   - Click **Alert** at the top
   - Click **Create Alert**

4. **Configure Alert:**
   - **Alert name:** EC2 High CPU
   - **Condition:** avg() of CPU > 80%
   - **For:** 5 minutes
   - **Send to:** Notifications (configure email/Slack first)

5. **Save:** Click **Save** dashboard

---

## 📱 STEP 9: Setup Notifications (Email/Slack)

### Email Notifications

1. **Go to Configuration** → **Notification channels**
2. Click **New channel**
3. **Type:** Email
4. **Email addresses:** your-email@example.com
5. **Send test notification**
6. **Save**

### Slack Notifications

1. **Create Slack webhook:**
   - Go to your Slack workspace
   - Settings → Apps & integrations → Incoming Webhooks
   - Create new webhook → Copy URL

2. **In Grafana:**
   - Configuration → Notification channels
   - Click **New channel**
   - **Type:** Slack
   - **Webhook URL:** [Paste Slack webhook]
   - **Channel:** #auto-heal-alerts
   - **Send test notification**
   - **Save**

---

## 🔍 STEP 10: Monitor Healing Logs

### Via Grafana

1. **Grafana → Explore**
2. **Data Source:** CloudWatch
3. **Query:**
   - **Namespace:** /aws/lambda
   - **Function:** auto-heal-infra-auto-heal
   - **Metrics:** Invocations, Duration, Errors

### Via AWS Console

1. **CloudWatch → Log Groups**
2. **Select:** `/aws/lambda/auto-heal-infra-auto-heal`
3. **View recent logs** to see healing actions taken

---

## 🎓 STEP 11: Interpret Dashboard Metrics

### Healthy State Indicators

✅ **CPU Utilization:** < 60%  
✅ **Memory Usage:** < 70%  
✅ **Disk Usage:** < 80%  
✅ **Lambda Errors:** 0  
✅ **Instance Health:** All green  
✅ **SNS Messages:** Low/none (no issues)

### Warning State (Action Required)

⚠️ **CPU:** 60-80% (monitor, may trigger healing)  
⚠️ **Memory:** 70-85% (check processes)  
⚠️ **Disk:** 80-90% (cleanup needed)  
⚠️ **Lambda Errors:** > 0 (check logs)  
⚠️ **Instance Health:** Any red  
⚠️ **SNS Messages:** Frequent (constant healing)

### Critical State (Immediate Action)

🔴 **CPU:** > 80% (healing triggered)  
🔴 **Memory:** > 85% (cache clearing + reboot)  
🔴 **Disk:** > 90% (cleanup + reboot)  
🔴 **Lambda Errors:** Multiple errors  
🔴 **Instance Health:** Failed checks  
🔴 **SNS Messages:** Continuous alerts

---

## 🛠️ STEP 12: Customize Dashboard

### Add Additional Panels

1. Click **Edit dashboard** (top right)
2. Click **Add panel** (+ button)
3. **Select visualization type:**
   - Graph = Time series data
   - Stat = Current value
   - Table = Data table
   - Gauge = Percentage metric
   - Pie chart = Distribution

4. **Add CloudWatch query:**
   - Data source: CloudWatch
   - Namespace: AWS/EC2 or AWS/Lambda
   - Metric: Select metric
   - Statistics: Average, Max, Min, Sum

5. **Configure title, legends, thresholds**
6. **Save dashboard**

### Clone or Duplicate Dashboard

1. Go to dashboard **Settings** (gear icon)
2. Click **Make a copy**
3. **Name:** New dashboard name
4. **Save**

---

## 📈 STEP 13: Advanced Queries

### Query Network Traffic

```
Namespace: AWS/EC2
Metric: NetworkIn
Statistics: Average
```

### Query EBS Volume I/O

```
Namespace: AWS/EBS
Metric: VolumeReadOps, VolumeWriteOps
Statistics: Sum
```

### Query Lambda Cost

```
Namespace: AWS/Lambda
Metric: Duration
Calculate: Duration × 0.0000002 (approximate cost)
```

---

## 🚨 STEP 14: Set Up Alerts for Healing Failures

### Configure Lambda Error Alert

1. **Edit dashboard**
2. **Select Lambda Activity panel**
3. **Alert tab**
4. **Condition:** when errors > 0
5. **Send to:** Email/Slack
6. **Message:** "🚨 Auto-Heal Lambda function failed"

---

## ✅ Verification Checklist

- [ ] Grafana is accessible at http://3.222.48.52:3000
- [ ] Changed default admin password
- [ ] CloudWatch data source is configured and tested
- [ ] Dashboard imported successfully
- [ ] All 7 panels display metrics
- [ ] Auto-refresh is set to 30 seconds
- [ ] Instance filter shows all target instances
- [ ] Lambda metrics showing current invocation data
- [ ] SNS alerts panel updating in real-time
- [ ] Email/Slack notifications configured (optional)
- [ ] Custom alerts created for critical thresholds
- [ ] CloudWatch logs accessible via Lambda link

---

## 🆘 Troubleshooting

### Dashboard Shows "No Data"

**Solution:**
```bash
# 1. Check CloudWatch agent is running on instances
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]'

# 2. Check logs are being published
aws cloudwatch describe-alarms --alarm-names auto-heal-cpu-alarm

# 3. Verify IAM permissions (Grafana instance role)
aws iam get-role-policy --role-name auto-heal-infra-grafana-role --policy-name grafana-policy
```

### Grafana Won't Connect to CloudWatch

**Solution:**
```bash
# 1. Check Grafana logs
ssh ec2-user@3.222.48.52 "sudo tail -f /var/log/grafana/grafana.log"

# 2. Verify IAM role has CloudWatch permissions
# 3. Restart Grafana
ssh ec2-user@3.222.48.52 "sudo systemctl restart grafana-server"
```

### Metrics Not Appearing

**Solution:**
1. Wait 5-10 minutes for CloudWatch agent to send first metrics
2. Verify instances have proper IAM role
3. Check CloudWatch agent is running:
   ```bash
   ssh ec2-user@<instance-ip> "sudo systemctl status amazon-cloudwatch-agent"
   ```

---

## 📚 Additional Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [CloudWatch Metrics Reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CW_Support_For_AWS.html)
- [Auto-Heal Project README](./README.md)
- [Deployment Guide](./DEPLOYMENT_GUIDE.md)

---

## 🎯 Next Steps

1. ✅ Monitor healing events in real-time
2. ✅ Verify auto-healing works (trigger test alarm)
3. ✅ Optimize alarm thresholds based on baseline metrics
4. ✅ Set up team notifications
5. ✅ Export dashboard for backup

---

**Dashboard Setup Completed!** 🎉  
All metrics are now being collected and visualized in real-time.

For issues or questions, refer to the Troubleshooting section above.
