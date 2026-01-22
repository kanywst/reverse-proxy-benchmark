#!/bin/bash

# Port mapping
# Traefik: 8081
# Pingora: 8082
# Envoy: 10000
# Nginx: 8084
set -e

# Build Proxies
echo "Building Pingora..."
cargo build --release --quiet --manifest-path pingora/Cargo.toml || { echo "Pingora build failed"; exit 1; }

# Build Upstream
echo "Building Upstream..."
go build -o upstream_bin upstream/main.go || { echo "Upstream build failed"; exit 1; }

# OS Tuning
ulimit -n 65536

echo "=== Starting Process Group Aware Benchmark ==="

# Start Upstream
./upstream_bin > /dev/null 2>&1 &
UPSTREAM_PID=$!

echo "Waiting for upstream..."
while ! nc -z 127.0.0.1 8080; do sleep 0.1; done
echo "Upstream started."

function cleanup() {
    echo "Cleaning up..."
    kill $UPSTREAM_PID 2>/dev/null
    pkill -P $$ 
    exit
}
trap cleanup SIGINT EXIT

PROXIES=("nginx:8084" "traefik:8081" "envoy:10000" "pingora:8082")

wait_for_port() {
    local port=$1
    local pid=$2
    local retries=0
    local max_retries=100
    while ! nc -z 127.0.0.1 $port; do
        sleep 0.1
        ((retries++))
        if [ $retries -ge $max_retries ]; then
            return 1
        fi
        if ! kill -0 $pid 2>/dev/null; then
            return 1
        fi
    done
    return 0
}

# Function to get total CPU and RSS for a process and all its children
get_pgroup_stats() {
    local parent_pid=$1
    # Check if pgrep is available (should be on macOS/Linux)
    # Get list of all PIDs in the hierarchy: parent + children
    # On macOS, pgrep -P works for direct children. We might need recursive lookups or just assume 1 level for Nginx.
    # Nginx usually has master -> workers.
    
    # Get all PIDs: the parent and any direct children
    local pids=$(pgrep -P $parent_pid)
    pids="$parent_pid $pids"
    
    # Sum CPU and RSS for all these PIDs
    # ps -o %cpu,rss -p <pid_list>
    # formatting output to remove header and sum up
    echo "$pids" | xargs ps -o %cpu=,rss= -p 2>/dev/null | awk '{cpu+=$1; mem+=$2} END {print cpu, mem}'
}

for p in "${PROXIES[@]}"; do
    NAME=${p%%:*}
    PORT=${p#*:}
    echo "------------------------------------------------"
    echo "Target: $NAME (Port $PORT)"

    # Start proxy
    case $NAME in
        nginx)
            /opt/homebrew/bin/nginx -c "$(pwd)/nginx/nginx.conf" -g 'daemon off;' > /dev/null 2>&1 &
            PID=$! ;;
        envoy)
            /opt/homebrew/bin/envoy -c "$(pwd)/envoy/envoy.yaml" --base-id 1 > /dev/null 2>&1 &
            PID=$! ;;
        traefik)
            /opt/homebrew/bin/traefik --configfile "$(pwd)/traefik/traefik.yml" > /dev/null 2>&1 &
            PID=$! ;;
        pingora)
            ./pingora/target/release/pingora-bench > /dev/null 2>&1 &
            PID=$! ;;
    esac

    if ! wait_for_port $PORT $PID; then
        echo "Skipping $NAME (Startup failed)"
        continue
    fi

    # Warm-up
    echo " Warming up..."
    wrk -t2 -c50 -d3s http://127.0.0.1:$PORT/ > /dev/null 2>&1

    # Resource Monitoring (High Frequency 0.1s, Process Group Aware)
    LOG_FILE="stats_${NAME}.log"
    rm -f $LOG_FILE
    (
        while kill -0 $PID 2>/dev/null; do
            # Capture stats for process tree
            get_pgroup_stats $PID >> $LOG_FILE
            sleep 0.1
        done
    ) &
    MONITOR_PID=$!
    disown $MONITOR_PID

    # Benchmark
    echo " Running Benchmark..."
    wrk -t12 -c100 -d10s http://127.0.0.1:$PORT/

    # Stop Monitoring
    kill $MONITOR_PID 2>/dev/null

    # Stats Calculation
    if [ -f $LOG_FILE ]; then
        echo " Resource Usage (Avg during test - Process Group):"
        awk '{cpu+=$1; mem+=$2; count++} END {if(count>0) print "  Avg CPU: " cpu/count "%, Avg RSS: " mem/1024/count " MB"}' $LOG_FILE
        rm $LOG_FILE
    fi

    kill $PID
    sleep 2
done

echo "Done."
