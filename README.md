# Reverse Proxy Benchmark

- [Reverse Proxy Benchmark](#reverse-proxy-benchmark)
  - [1. Prerequisites](#1-prerequisites)
  - [2. Usage](#2-usage)
    - [Step 1: Start Upstream Server](#step-1-start-upstream-server)
    - [Step 2: Start Proxies (in separate terminals)](#step-2-start-proxies-in-separate-terminals)
    - [Step 3: Benchmark (wrk)](#step-3-benchmark-wrk)
  - [3. Batch Benchmark Scripts](#3-batch-benchmark-scripts)
    - [Mode 1: Max Performance (`./scripts/bench_perf.sh`)](#mode-1-max-performance-scriptsbench_perfsh)
    - [Mode 2: Resource Analysis (`./scripts/bench_resources.sh`)](#mode-2-resource-analysis-scriptsbench_resourcessh)
  - [4. Benchmark Results (Reference)](#4-benchmark-results-reference)
    - [Analysis](#analysis)
  - [5. Detailed Benchmark (Process Group Aware)](#5-detailed-benchmark-process-group-aware)
  - [6. Final Consolidated Benchmark Results](#6-final-consolidated-benchmark-results)
  - [Final Conclusion](#final-conclusion)

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

## 3. Batch Benchmark Scripts

To ensure accuracy, the benchmark is split into two modes to avoid the "Observer Effect" where heavy monitoring degrades performance.

### Mode 1: Max Performance (`./scripts/bench_perf.sh`)

Runs `wrk` with **no monitoring overhead**. Use this to measure the true maximum throughput and latency.

```bash
./scripts/bench_perf.sh
```

### Mode 2: Resource Analysis (`./scripts/bench_resources.sh`)

Runs `wrk` while heavily monitoring the **entire process group** (CPU/Memory).
> **Note:** Throughput will be lower in this mode due to the monitoring overhead. Use these results only for resource consumption analysis, not for performance scoring.

```bash
./scripts/bench_resources.sh
```

## 4. Benchmark Results (Reference)

Executed on 2026/01/23 (MacBook Pro M1 Max / 32GB RAM)

|    Proxy    | Requests/Sec | Transfer/Sec | Avg CPU | Avg RSS | Errors |
| :---------: | :----------: | :----------: | :-----: | :-----: | :----: |
|  **Nginx**  |    73,060    |   10.38 MB   |   0%*   | 4.23 MB |   0    |
|  **Envoy**  |    46,326    |   6.72 MB    |  464%   | 42.05 MB|   0    |
| **Pingora** |    35,444    |   4.29 MB    |   84%   | 18.61 MB|   0    |
| **Traefik** |    9,171     |   8.95 MB    |   0%*   | 59.01 MB|   0    |

\* 0% CPU values in the logs may be due to sampling timing or highly efficient event-driven architectures.

### Analysis

- **Nginx** demonstrated exceptional throughput (73k+ Req/Sec) and the lowest memory usage.
- **Envoy** followed with high throughput but showed significantly higher CPU utilization in this environment.
- **Pingora** provided stable performance with moderate CPU and memory consumption.
- **Traefik** showed the lowest throughput among the tested proxies but maintained zero errors.
- All proxies achieved **zero errors** in this benchmark run.

> **Note on CPU Usage:**
> The CPU usage for **Nginx** and **Traefik** appears as 0% in the table above. This is likely due to the original benchmark script (`./scripts/bench.sh`) only monitoring the master process ID.
> - **Nginx** uses worker processes to handle traffic, so the master process remains idle.
> - **Traefik** and **Envoy** differences might stem from threading models vs process models or sampling timing.
>
> A improved script `./scripts/bench_pgroup.sh` has been created to monitor the entire process group (including child processes) for more accurate resource tracking.

## 5. Detailed Benchmark (Process Group Aware)

Executed with `./scripts/bench_pgroup.sh` on 2026/01/23.

|    Proxy    | Requests/Sec | Transfer/Sec | Avg CPU (Total) | Avg RSS (Total) |
| :---------: | :----------: | :----------: | :-------------: | :-------------: |
|  **Nginx**  |    74,047    |   10.52 MB   |     92.76%      |    12.81 MB     |
|  **Envoy**  |    28,524    |   4.14 MB    |     330.84%     |    44.56 MB     |
| **Pingora** |    20,820    |   2.52 MB    |     70.98%      |    18.83 MB     |
| **Traefik** |    8,297     |   8.09 MB    |      0%*        |    58.81 MB     |

\* Traefik's CPU remains at 0% in this run, suggesting it may still be spawning processes or using threads in a way that escapes current PID tracking, or it was under-utilized during this specific run.

## 6. Final Consolidated Benchmark Results

Executed on MacBook Pro M1 Max

The values below combine the **Max Throughput** (from `./scripts/bench_perf.sh`) and **Resource Usage** (from `./scripts/bench_resources.sh`) to give a complete picture.

|    Proxy    | Max Requests/Sec | Transfer/Sec | Avg CPU (Total) | Avg RSS (Total) |
| :---------: | :--------------: | :----------: | :-------------: | :-------------: |
|  **Nginx**  |    **54,826**    | **7.79 MB**  |       80%       |  **11.97 MB**   |
|  **Envoy**  |      37,637      |   5.46 MB    |      383%       |    43.30 MB     |
| **Pingora** |      30,991      |   3.75 MB    |       77%       |    19.60 MB     |
| **Traefik** |      8,603       |   8.39 MB    |       0%*       |    60.96 MB     |

\* *Traefik's CPU usage remains elusive under this monitoring method, likely due to ephemeral processes or specific Go runtime behaviors on macOS.*

## Final Conclusion

- **Nginx** remains the efficiency king, delivering the highest throughput with the lowest memory footprint.
- **Envoy** scales well across multiple cores (high CPU usage) to deliver strong performance, but is heavier on resources.
- **Pingora** offers a balanced profile, with good performance and reasonable resource usage, sitting between Nginx and Envoy.
- **Traefik** prioritizes features and ease of use over raw throughput in this specific "hello world" benchmark scenario.
