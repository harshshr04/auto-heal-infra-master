# 🎯 Integrated Dashboard - Quick Start Guide

## Overview

This guide helps you access and use the custom integrated dashboard that combines:
- ✅ Grafana metrics visualization
- ✅ Nagios monitoring integration  
- ✅ Real-time system metrics (CPU, Memory, Disk)
- ✅ Lambda function monitoring
- ✅ Modern UI with clickable Nagios actions

## 📊 Dashboard Features

### 1. **Metrics Cards**
- **CPU Utilization**: Real-time CPU usage with threshold alerts
- **Memory Utilization**: RAM usage monitoring
- **Disk Utilization**: Storage space tracking
- Visual progress bars and status indicators (OK/WARNING/CRITICAL)

### 2. **Lambda Monitoring**
- Total invocations (24-hour window)
- Average execution time
- Error rate calculation
- Status indicator

### 3. **Nagios Integration Panel**
Click-to-act monitoring dashboard:
- **Monitored Hosts**: View all hosts status (2-click access to Nagios)
- **Services**: See service status (2-click access to Nagios)
- **Problems**: View critical issues (2-click access to Nagios)
- **Recent Alerts**: Last 24-hour alerts (2-click access to Nagios)

### 4. **SNS Pipeline**
- Messages published count
- Active topics
- Last alert timestamp
- Direct link to AWS SNS dashboard

### 5. **Healing Activity Log**
Real-time feed of:
- Successful healing actions (✓ green)
- Failed healing attempts (✗ red)
- Timestamps and descriptions
- Link to CloudWatch logs

---

## 🚀 How to Access

### **Option 1: Local Access (Easiest)**
```bash
# Navigate to dashboard folder
cd /Users/kumarmangalam/Desktop/Devops/auto-heal-infra/dashboard

# Open in browser
open custom-integrated-dashboard.html
```

### **Option 2: Python HTTP Server**
```bash
cd /Users/kumarmangalam/Desktop/Devops/auto-heal-infra/dashboard
python3 -m http.server 8000
```
Then visit: **http://localhost:8000/custom-integrated-dashboard.html**

### **Option 3: Deploy to Grafana Server**
```bash
# Copy dashboard to Grafana server
scp dashboard/custom-integrated-dashboard.html \
    ec2-user@3.222.48.52:/tmp/

# SSH into Grafana server
ssh ec2-user@3.222.48.52

# Copy to web root
sudo cp /tmp/custom-integrated-dashboard.html /var/www/html/
sudo chown www-data:www-data /var/www/html/custom-integrated-dashboard.html
```

Access via: **http://3.222.48.52/custom-integrated-dashboard.html**

### **Option 4: Embed in Grafana**
1. Login to Grafana: http://3.222.48.52:3000
2. Create new dashboard
3. Add HTML panel
4. Copy dashboard HTML code

---

## 🎨 Using the Dashboard

### **Viewing Metrics**
- Metrics update automatically every 30 seconds
- Color-coded status indicators:
  - 🟢 **Green**: Normal (< 80% threshold)
  - 🟠 **Orange**: Warning (80-90%)
  - 🔴 **Red**: Critical (> 90%)

### **Clicking Nagios Actions**
All Nagios action cards are clickable:

1. **Click any card** (Monitored Hosts, Services, Problems, Alerts)
2. **Redirects to Nagios** with filtered view
3. **Nagios login**: 
   - Username: `nagiosadmin`
   - Password: `nagios` (or your updated password)

### **Monitoring Activity**
- Scroll through recent healing activities in bottom panel
- Green = successful healing
- Red = failed action (requires investigation)
- Click "View CloudWatch Logs" for detailed logs

### **Quick Links**
- 📊 **Nagios Console**: Top-right button
- 📈 **SNS Dashboard**: Link in SNS card
- 📋 **CloudWatch Logs**: Link in Activity panel

---

## 🔧 Customization

### **Modify URLs**
Edit the CONFIG object in HTML file:
```javascript
const CONFIG = {
    grafanaUrl: 'http://3.222.48.52:3000',
    nagiosUrl: 'http://3.219.108.146/nagios',
    cloudwatchRegion: 'us-east-1',
    refreshInterval: 30000,
    thresholds: {
        cpu: 80,
        memory: 85,
        disk: 90
    }
};
```

### **Change Thresholds**
```javascript
thresholds: {
    cpu: 90,        // Change to your desired CPU threshold
    memory: 95,     // Memory threshold
    disk: 95        // Disk threshold
}
```

### **Adjust Refresh Interval**
```javascript
refreshInterval: 15000  // Change 30s to 15s, etc.
```

### **Add Custom Panels**
The dashboard uses standard HTML/CSS/JS. You can:
- Add new metric cards
- Change colors and fonts
- Add charts and graphs
- Integrate with APIs

---

## 📊 Connecting to Real Data

### **Option A: CloudWatch API**
```javascript
// Add to JavaScript section
async function getCloudWatchMetrics() {
    const response = await fetch('YOUR_API_ENDPOINT');
    const data = await response.json();
    updateMetric('cpu', data.cpuUtilization);
}
```

### **Option B: Grafana API**
```javascript
// Query Grafana datasources
const response = await axios.get(
    'http://3.222.48.52:3000/api/datasources/proxy/1/query',
    {
        auth: { username: 'admin', password: 'admin' }
    }
);
```

### **Option C: Nagios API**
```javascript
// Query Nagios status
const response = await fetch(
    'http://3.219.108.146/nagios/cgi-bin/statusxml.cgi?servicestatus'
);
```

---

## 🎯 Common Tasks

### **Change Nagios Password**
```bash
# SSH to Nagios instance
ssh ec2-user@3.219.108.146

# Update password
sudo htpasswd /usr/local/nagios/etc/htpasswd.users nagiosadmin
# Enter new password twice
```

### **View Current Metrics**
Check real metrics via AWS CLI:
```bash
# CPU Metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --start-time 2025-11-01T00:00:00Z \
  --end-time 2025-11-01T23:59:59Z \
  --period 300 \
  --statistics Average \
  --region us-east-1

# Memory Metrics (CloudWatch Agent)
aws cloudwatch get-metric-statistics \
  --namespace auto-heal-infra \
  --metric-name mem_used_percent \
  --start-time 2025-11-01T00:00:00Z \
  --end-time 2025-11-01T23:59:59Z \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

### **Check Lambda Activity**
```bash
# View Lambda logs
aws logs tail /aws/lambda/auto-heal-infra-auto-heal --follow

# Get Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=auto-heal-infra-auto-heal \
  --start-time 2025-11-01T00:00:00Z \
  --end-time 2025-11-01T23:59:59Z \
  --period 300 \
  --statistics Sum \
  --region us-east-1
```

---

## 🐛 Troubleshooting

### **Dashboard won't load**
- Check browser console (F12)
- Ensure URLs in CONFIG are accessible
- Verify CORS if using API calls

### **Metrics show "0" or "-"**
- Dashboard uses mock data by default
- Connect to real API endpoints
- Check CloudWatch agent on EC2 instances

### **Nagios links not working**
- Verify Nagios URL is correct
- Check security group allows port 80
- Confirm Nagios credentials

### **Auto-refresh not working**
- Check JavaScript console for errors
- Verify API endpoints are accessible
- Increase refresh interval if network is slow

---

## 📈 Next Steps

1. ✅ **Deploy dashboard** to production server
2. ✅ **Connect to real APIs** for live metrics
3. ✅ **Customize appearance** to match your brand
4. ✅ **Add more panels** (alerts, trends, reports)
5. ✅ **Setup monitoring** for dashboard itself
6. ✅ **Document procedures** for your team

---

## 📚 Resources

- [Grafana Documentation](https://grafana.com/docs/)
- [Nagios Documentation](https://www.nagios.org/documentation/)
- [AWS CloudWatch API](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/)
- [Chart.js Documentation](https://www.chartjs.org/docs/latest/)

---

**Dashboard Version**: 1.0  
**Last Updated**: November 1, 2025  
**Created for**: Auto-Heal Infrastructure Project
