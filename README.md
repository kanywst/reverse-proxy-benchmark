# Reverse Proxy Benchmark

- [Reverse Proxy Benchmark](#reverse-proxy-benchmark)
  - [1. Prerequisites](#1-prerequisites)
  - [2. Usage](#2-usage)
    - [Step 1: Start Upstream Server](#step-1-start-upstream-server)
    - [Step 2: Start Proxies (in separate terminals)](#step-2-start-proxies-in-separate-terminals)
    - [Step 3: Benchmark (wrk)](#step-3-benchmark-wrk)
  - [3. Batch Benchmark Script](#3-batch-benchmark-script)
  - [4. Benchmark Results (Reference)](#4-benchmark-results-reference)
    - [Analysis](#analysis)

Directly measure performance of Nginx, Envoy, Traefik, and Pingora.

## 1. Prerequisites

```bash
# Install dependencies
brew install wrk nginx envoy traefik rustup
rustup-init -y

# Increase OS limits (prevent connection starvation)
ulimit -n 65536
sudo sysctl -w net.inet.ip.portrange.first=16384
```

## 2. Usage

### Step 1: Start Upstream Server

```bash
cd upstream
go run main.go
```

### Step 2: Start Proxies (in separate terminals)

**Nginx:**

```bash
nginx -c $(pwd)/nginx/nginx.conf -g 'daemon off;'
```

**Envoy:**

```bash
envoy -c envoy/envoy.yaml
```

**Traefik:**

```bash
traefik --configfile traefik/traefik.yml
```

**Pingora:**

```bash
cd pingora
cargo run --release
```

### Step 3: Benchmark (wrk)

```bash
# Example: Pingora
wrk -t12 -c100 -d30s http://127.0.0.1:8082/
```

## 3. Batch Benchmark Script

Run `./bench.sh` to sequentially benchmark all proxies and display the results.

## 4. Benchmark Results (Reference)

Executed on 2026/01/21 (MacBook Pro M1 Max / 32GB RAM)

|    Proxy    | Requests/Sec | Transfer/Sec |        Errors        |
| :---------: | :----------: | :----------: | :------------------: |
|  **Envoy**  |    39,265    |   5.72 MB    |   1,763 (Non-2xx)    |
|  **Nginx**  |    39,222    |   5.58 MB    |    684 (Non-2xx)     |
| **Pingora** |    32,829    |   3.98 MB    |        **0**         |
| **Traefik** |    8,002     |   7.81 MB    | 0 (8 connect errors) |

### Analysis

- **Envoy** and **Nginx** achieved the highest throughput but encountered some errors (non-2xx responses) under high load.
- **Pingora** demonstrated performance close to Nginx/Envoy while maintaining **zero errors**, indicating high stability under load.
- **Traefik** showed more modest throughput compared to the other proxies in this configuration.
