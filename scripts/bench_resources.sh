#!/bin/bash
set -e

# Build Proxies
echo "Building Pingora..."
cargo build --release --quiet --manifest-path pingora/Cargo.toml || { echo "Pingora build failed"; exit 1; }

echo "Building Upstream..."
go build -o upstream_bin upstream/main.go || { echo "Upstream build failed"; exit 1; }

ulimit -n 65536

echo "=== Mode 2: Resource Usage Analysis (Process Group Aware) ==="
echo "NOTE: Throughput will be lower due to heavy monitoring overhead."

# Start Upstream
./upstream_bin > /dev/null 2>&1 &
UPSTREAM_PID=$!

while ! nc -z 127.0.0.1 8080; do sleep 0.1; done

function cleanup() {
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
    while ! nc -z 127.0.0.1 $port; do
        sleep 0.1
        ((retries++))
        if [ $retries -ge 100 ]; then return 1; fi
        if ! kill -0 $pid 2>/dev/null; then return 1; fi
    done
    return 0
}

get_pgroup_stats() {
    local parent_pid=$1
    local pids=$(pgrep -P $parent_pid)
    pids="$parent_pid $pids"
    echo "$pids" | xargs ps -o %cpu=,rss= -p 2>/dev/null | awk '{cpu+=$1; mem+=$2} END {print cpu, mem}'
}

for p in "${PROXIES[@]}"; do
    NAME=${p%%:*}
    PORT=${p#*:}
    echo "------------------------------------------------"
    echo "Target: $NAME"

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

    wait_for_port $PORT $PID

    # Warm-up
    echo " Warming up..."
    wrk -t2 -c50 -d3s http://127.0.0.1:$PORT/ > /dev/null 2>&1

    # Monitor
    LOG_FILE="stats_${NAME}.log"
    rm -f $LOG_FILE
    (
        while kill -0 $PID 2>/dev/null; do
            get_pgroup_stats $PID >> $LOG_FILE
            sleep 0.1
        done
    ) &
    MONITOR_PID=$!
    disown $MONITOR_PID

    # Load Generation (Output suppressed as it is not the focus)
    echo " Generating Load (10s)..."
    wrk -t12 -c100 -d10s http://127.0.0.1:$PORT/ > /dev/null 2>&1

    kill $MONITOR_PID 2>/dev/null

    # Report
    if [ -f $LOG_FILE ]; then
        echo " Resource Usage (Avg Total):"
        awk '{cpu+=$1; mem+=$2; count++} END {if(count>0) print "  Avg CPU: " cpu/count "%, Avg RSS: " mem/1024/count " MB"}' $LOG_FILE
        rm $LOG_FILE
    fi

    kill $PID
    sleep 2
done
