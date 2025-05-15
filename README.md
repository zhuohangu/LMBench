# LMBench

Online Kubernetes-based benchmarking.

# How to Use

Clone to run on your local machine or submit a PR (or directly push if you have access) to run it on a LMCache GPU runner (will trigger on push).

# Running a benchmark

`bench-spec.yaml` is the only file you need to modify

See `bench-spec-TEMPLATE.yaml` for all of the current configuration options

If you are running locally (instead of on the LMCache runner):

1. Make sure you have a virtual environment with python >=3.12 activated.

2. Install `requirements.txt`

3. Manually run `run-bench.py` (3 stages are infrastructure, serving engines, workloads)

`python run-bench.py` is default (`--start-from 1`)

If you want to start directly from the workload stage (you already have infrastructure and serving engines set up), you can run:
`python run-bench.py --start-from 3 --model-url meta-llama/Llama-3.1-8B-Instruct --hf-token <your-hf-token> --key 'stack'`

# Extending the benchmarks

Please add additional dispatch logic to `run-bench.py` to help it parse more options
in `bench-spec.yaml` and update `bench-spec-TEMPLATE` with a comment in the proper place

# May 7th, 2025 First GKE Run

[demo](https://www.youtube.com/watch?v=KRQbiKFtlqU)

Production Stack v0 and v1 (should) be supported and all 4 workflows (Agentic, Synthetic, ShareGPT, and Mooncake)
First GKE run worked with:

```yaml
Infrastructure:
  Location: LMCacheGKE
  numClusterGPUs: 1

Serving:
  Baseline: ProductionStack
    vLLM-Version: 0
    useLMCache: true
    modelURL: meta-llama/Llama-3.1-8B-Instruct
    replicaCount: 1
    numGPUs: 1
    tensorParallelSize: 1
    hf_token: <HF_TOKEN>
    maxModelLen: 16384

Workload:
  ShareGPT
    LIMIT: 100
    MIN_ROUNDS: 5
    START_ROUND: 3
    QPS: [1.34, 2]
```

# May 5th, 2025 Minimal Viable Product

Only a Minikube, ProductionStack, and ShareGPT works right now!

[demo](https://www.youtube.com/watch?v=z3aw-ubZWms)

`bench-spec.yaml`

```yaml
Infrastructure:
  Location: Minikube

Serving:
  Baseline: ProductionStack
    vLLM-Version: 0
    useLMCache: true
    modelURL: meta-llama/Llama-3.1-8B-Instruct
    replicaCount: 1
    numGPUs: 1
    tensorParallelSize: 1
    hf_token: <HF_TOKEN>
    maxModelLen: 16384

Workload:
  ShareGPT
    LIMIT: 100
    MIN_ROUNDS: 5
    START_ROUND: 3
    QPS: [1.34, 2]
```