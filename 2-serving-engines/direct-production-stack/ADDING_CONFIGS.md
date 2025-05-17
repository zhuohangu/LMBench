# Requirements

Please render the production stack helm template as such

Go to (clone and cd) production-stack/helm

```bash
helm template vllm . -f values.yaml > YOUR_NEW_CONFIG.yaml
```

Please use the `vllm` release name.

Tips when modifying `helm/values.yaml`
- make sure the vllm api key remains commented out (or else the open ai client has to know the key)
- start uncommenting from modelSpec
- remove the line      "runtimeClassName: nvidia" (or any line containing "runtimeClassName")
- substitute lmcacheConfig.enabled: {true, false}
- comment out modelSpec: []
- remove line      enableChunkedPrefill: false (or any line containing "enableChunkedPrefill")
- substitute modelURL, name, and model entries (key names) with the given modelURL from bench-spec.yaml
- change "LMCacheConnector" to "LMCacheConnectorV1"
- increase the PVC size to 180Gi