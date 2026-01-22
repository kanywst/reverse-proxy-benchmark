#!/bin/bash
set -e

# Port mapping
# Traefik: 8081
# Pingora: 8082
# Envoy: 10000
# Nginx: 8084

# Build Proxies
echo "Building Pingora..."
cargo build --release --quiet --manifest-path pingora/Cargo.toml || { echo "Pingora build failed"; exit 1; }

echo "Building Upstream..."
go build -o upstream_bin upstream/main.go || { echo "Upstream build failed"; exit 1; }

ulimit -n 65536

echo "=== Mode 1: Max Performance Benchmark (No Monitoring Overhead) ==="

# Start Upstream
./upstream_bin > /dev/null 2>&1 &
UPSTREAM_PID=$!

echo "Waiting for upstream..."
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

    if ! wait_for_port $PORT $PID; then
        echo "Skipping $NAME (Startup failed)"
        continue
    fi

    # Warm-up
    echo " Warming up..."
    wrk -t2 -c50 -d3s http://127.0.0.1:$PORT/ > /dev/null 2>&1

    # Benchmark (Pure)
    echo " Running Performance Test..."
    wrk -t12 -c100 -d10s http://127.0.0.1:$PORT/

    kill $PID
    sleep 2
done
