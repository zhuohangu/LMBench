# How to request a run on the LMCache GPU runner:

1. Reason/Description:

Please describe here what your goal is.

2. Modify `bench-spec.yaml`

Example:
```yaml
Infrastructure:
  Location: LMCacheGKE
  numClusterGPUs: 1

Serving:
  Baseline: ProductionStack
  ProductionStack:
    vLLM-Version: 0
    useLMCache: true
    cpuSize: 60
    modelURL: meta-llama/Llama-3.1-8B-Instruct
    replicaCount: 1
    numGPUs: 1
    tensorParallelSize: 1
    hf_token: <YOUR_HF_TOKEN>
    maxModelLen: 16384

Workload:
  ShareGPT:
    LIMIT: 100
    MIN_ROUNDS: 5
    START_ROUND: 3
    QPS: [1.34, 2]
```

3. Submit PR and once we accept, yoru benchmark will run and you will able to see
it in the Actions tab as an artifact.

TODO: we will also support a dashboard to help you see the latest results.