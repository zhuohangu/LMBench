#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
LIMIT=1000
MIN_ROUNDS=5
START_ROUND=3
MODEL_URL=""

# Parse arguments (supports both short and long options)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--limit)
      LIMIT="$2"
      shift 2
      ;;
    -m|--min_rounds)
      MIN_ROUNDS="$2"
      shift 2
      ;;
    -s|--start_round)
      START_ROUND="$2"
      shift 2
      ;;
    --model-url)
      MODEL_URL="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Usage: $0 [-l limit] [-m min_rounds] [-s start_round] [--model-url <url>]"
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Calculate round_number as start_round - 1.
ROUND_NUMBER=$((START_ROUND - 1))

# Download the JSON file.
wget https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json

# Run Python preprocessing scripts with the parsed parameters.
python3 data_preprocessing.py --parse 1 --model-url "$MODEL_URL"
python3 concat_input.py --limit "$LIMIT"
python3 prepare_run_dataset.py --min_rounds "$MIN_ROUNDS" --start_round "$START_ROUND"
python3 prepare_warmup_dataset.py --min_rounds "$MIN_ROUNDS" --round_number "$ROUND_NUMBER"

# Clean up temporary files
files=(
  "modified_file.json"
  "ShareGPT.json"
  "ShareGPT_V3_unfiltered_cleaned_split.json"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    rm "$file" && echo "Deleted: $file" || echo "Failed to delete: $file"
  else
    echo "File not found: $file"
  fi
done

# Move artifacts
mv warmup.json .. && echo "Moved warmup.json"
mv run.json .. && echo "Moved run.json"
