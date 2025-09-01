#!/bin/bash
# modern_privoxy_stats_top20.sh

LOGFILES="/var/log/privoxy/logfile*"
OUTFILE="/var/www/html/stats.html"
REQ_FILE="/var/www/html/requests.html"
JS_DIR="/var/www/html/js"

mkdir -p "$JS_DIR"

# Download Chart.js locally if not present
if [ ! -f "$JS_DIR/chart.min.js" ]; then
    wget -q -O "$JS_DIR/chart.min.js" https://cdn.jsdelivr.net/npm/chart.js
fi

TMPDIR=$(mktemp -d)
IP_FILE="$TMPDIR/ip.txt"
CODE_FILE="$TMPDIR/codes.txt"
HOST_FILE="$TMPDIR/hosts.txt"

# Check logs exist
if ! ls $LOGFILES 1> /dev/null 2>&1; then
    echo "No log files found at $LOGFILES"
    exit 1
fi

# Calculate total requests
TOTAL_REQUESTS=$(cat $LOGFILES | wc -l)
echo "<h1>Total Requests: $TOTAL_REQUESTS</h1>" > "$REQ_FILE"

# Top IPs
awk '{print $1}' $LOGFILES | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr > "$IP_FILE"

# HTTP response codes
awk '{print $9}' $LOGFILES | sort | uniq -c | sort -nr > "$CODE_FILE"

# Top requested hosts
awk -F\" '{
    split($2,a," ");
    if (a[1]=="CONNECT") {
        split(a[2],b,":"); print b[1]
    } else if (a[1]=="GET" || a[1]=="POST") {
        if (a[2] ~ /^http/) {
            gsub(/https?:\/\//,"",a[2]);
            split(a[2],b,"/"); print b[1]
        }
    }
}' $LOGFILES | sort | uniq -c | sort -nr > "$HOST_FILE"

# Functions to convert to JS arrays
to_js_labels_n() { local f=$1 n=$2; head -n $n "$f" | awk '{printf "\"%s (%s)\",", $2,$1}' | sed 's/,$//'; }
to_js_data_n() { local f=$1 n=$2; head -n $n "$f" | awk '{printf "%s,", $1}' | sed 's/,$//'; }
to_js_labels_simple_n() { local f=$1 n=$2; head -n $n "$f" | awk '{printf "\"%s\",", $2}' | sed 's/,$//'; }
to_js_data_simple_n() { local f=$1 n=$2; head -n $n "$f" | awk '{printf "%s,", $1}' | sed 's/,$//'; }

TOP_IP_LABELS=$(to_js_labels_n "$IP_FILE" 20)
TOP_IP_DATA=$(to_js_data_n "$IP_FILE" 20)

HOST_LABELS=$(to_js_labels_simple_n "$HOST_FILE" 20)
HOST_DATA=$(to_js_data_n "$HOST_FILE" 20)

CODE_LABELS=$(to_js_labels_simple_n "$CODE_FILE" 10)
CODE_DATA=$(to_js_data_n "$CODE_FILE" 10)

# Generate HTML (same as your template)
cat <<EOF > "$OUTFILE"
<!DOCTYPE html>
<html>
<head>
  <title>Privoxy Log Stats</title>
  <script src="js/chart.min.js"></script>
  <style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #121212; color: #e0e0e0; margin: 20px; }
    h1 { text-align: center; color: #00bcd4; }
    h2 { margin-top: 40px; color: #00bcd4; }
    .chart-container { width: 90%; max-width: 900px; margin: 30px auto; background: #1e1e1e; padding: 20px; border-radius: 10px; box-shadow: 0 0 15px rgba(0,0,0,0.7); }
    canvas { background: #1e1e1e; border-radius: 10px; }
  </style>
</head>
<body>
  <h1>Privoxy Log Statistics</h1>
  <h2>Total Requests: $TOTAL_REQUESTS</h2>

  <h2>Top 20 Client IPs</h2>
  <div class="chart-container"><canvas id="ipChart"></canvas></div>

  <h2>HTTP Response Codes</h2>
  <div class="chart-container"><canvas id="codeChart"></canvas></div>

  <h2>Top 20 Requested Hosts</h2>
  <div class="chart-container"><canvas id="hostChart"></canvas></div>

  <script>
  const chartOptions = { 
      responsive: true, 
      plugins: { legend: { labels: { color: '#e0e0e0' } } }, 
      scales: { x: { ticks: { color: '#e0e0e0' } }, y: { ticks: { color: '#e0e0e0' } } } 
  };

  function generateColors(count) {
      const colors = [];
      for (let i=0; i<count; i++) {
          const hue = Math.floor((360 / count) * i);
          colors.push(\`hsl(\${hue}, 70%, 50%)\`);
      }
      return colors;
  }

  new Chart(document.getElementById('ipChart'), {
    type: 'bar',
    data: { labels: [${TOP_IP_LABELS:-"\"No data\""}], datasets:[{ label:'Requests', data:[${TOP_IP_DATA:-0}], backgroundColor:'rgba(0,188,212,0.7)' }] },
    options: chartOptions
  });

  new Chart(document.getElementById('codeChart'), {
    type: 'pie',
    data: { labels: [${CODE_LABELS:-"\"No data\""}], datasets:[{ data:[${CODE_DATA:-0}], backgroundColor: generateColors([${CODE_LABELS:-"\"No data\""}].length) }] },
    options: { plugins:{ legend:{ labels:{ color:'#e0e0e0' } } } }
  });

  new Chart(document.getElementById('hostChart'), {
    type: 'bar',
    data: { labels: [${HOST_LABELS:-"\"No data\""}], datasets:[{ label:'Requests', data:[${HOST_DATA:-0}], backgroundColor:'rgba(255,64,129,0.7)' }] },
    options: chartOptions
  });
  </script>
</body>
</html>
EOF

rm -rf "$TMPDIR"
echo "Modern dark-themed stats written to $OUTFILE"
echo "Total requests written to $REQ_FILE"
