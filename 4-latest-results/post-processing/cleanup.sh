#!/bin/bash
set -e

# Replace all hf_token values with <YOUR_HF_TOKEN> in all .yaml files
find . -type f -name "*.yaml" -exec sed -i 's/^\(\s*-*\s*hf_token:\s*\).*/\1<YOUR_HF_TOKEN>/' {} \;
