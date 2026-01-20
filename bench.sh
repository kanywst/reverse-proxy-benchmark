#!/bin/bash

# Port mapping
# Traefik: 8081
# Pingora: 8082
# Envoy: 10000
# Nginx: 8084

# OS Tuning
ulimit -n 65536

echo "=== Starting Native Benchmark ==="

# 1. Start Upstream
go run upstream/main.go > /dev/null 2>&1 &
UPSTREAM_PID=$!
sleep 2

function cleanup() {
    echo "Cleaning up..."
    kill $UPSTREAM_PID 2>/dev/null
    exit
}
trap cleanup SIGINT

PROXIES=("nginx:8084" "traefik:8081" "envoy:10000" "pingora:8082")

for p in "${PROXIES[@]}"; do
    NAME=${p%%:*}
    PORT=${p#*:}
    echo "--- Testing $NAME (Port $PORT) ---"

    # Start proxy based on name
    case $NAME in
        nginx)
            /opt/homebrew/bin/nginx -c $(pwd)/nginx/nginx.conf -g 'daemon off;' > /dev/null 2>&1 &
            PID=$!
            ;;
        envoy)
            /opt/homebrew/bin/envoy -c $(pwd)/envoy/envoy.yaml --base-id 1 > /dev/null 2>&1 &
            PID=$!
            ;;
        traefik)
            /opt/homebrew/bin/traefik --configfile $(pwd)/traefik/traefik.yml > /dev/null 2>&1 &
            PID=$!
            ;;
        pingora)
            cd pingora && ./target/release/pingora-bench > /dev/null 2>&1 &
            PID=$!
            cd ..
            ;;
    esac

    sleep 3

    # Run Benchmark
    wrk -t12 -c100 -d10s http://127.0.0.1:$PORT/

    # Resource snapshot
    ps -o %cpu,rss -p $PID

    kill $PID
    sleep 2
done

kill $UPSTREAM_PID
echo "Done."
