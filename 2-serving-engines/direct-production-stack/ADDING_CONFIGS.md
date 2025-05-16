# Requirements

Please render the production stack helm template as such

Go to (clone and cd) production-stack/helm

```bash
helm template vllm . -f values.yaml > YOUR_NEW_CONFIG.yaml
```

Please use the `vllm` release name.