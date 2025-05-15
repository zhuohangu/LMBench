import pandas as pd
import sys
from typing import Optional
import os
import io
import contextlib
from datetime import datetime
import yaml

def ProcessSummary(
    df: pd.DataFrame,
    start_time: Optional[float] = None,
    end_time: Optional[float] = None,
    pending_queries: int = 0,
    qps: Optional[float] = None,
) -> str:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        if start_time is not None and end_time is not None:
            launched_queries = len(df.query(f"{start_time} <= launch_time <= {end_time}"))
            df = df.query(f"{start_time} <= finish_time <= {end_time}")
        else:
            launched_queries = len(df)

        print(
            f"Launched queries: {launched_queries}, "
            f"pending queries: {pending_queries}, "
            f"finished queries: {len(df)}"
        )

        if qps is None:
            qps = 0.0

        if start_time is None:
            start_time = df["launch_time"].min()
        if end_time is None:
            end_time = df["finish_time"].max()

        total_time = end_time - start_time
        total_requests = launched_queries + pending_queries
        finished_qps = len(df) / total_time
        _qps = total_requests / total_time

        total_prompt_tokens = df["prompt_tokens"].sum()
        total_generation_tokens = df["generation_tokens"].sum()
        average_prefill_speed = total_prompt_tokens / total_time
        average_generation_speed = total_generation_tokens / total_time
        average_generation_speed_per_request = (
            df["generation_tokens"] / df["generation_time"]
        ).replace([float('inf'), -float('inf')], float('nan')).dropna().mean()
        average_ttft = df["ttft"].mean()

        df = df[df['generation_tokens'] != 0].copy()
        df['ratio'] = df['generation_time'] / df['generation_tokens']
        average_ratio = df['ratio'].mean()

        print("\n==================== Performance summary ======================")
        print(f"  Processing speed: {finished_qps:.4f} reqs/s")
        print(f"  Input tokens per second: {average_prefill_speed:.4f} tokens/s")
        print(f"  Output tokens per second: {average_generation_speed:.4f} tokens/s")
        print(f"  Average generation throughput (per request): {average_generation_speed_per_request:.4f} tokens/req/s")
        print(f"  Average TTFT: {average_ttft:.4f}s")
        print(f"  Average generation_time / generation_tokens (Inter-Token Latency): {average_ratio:.4f}")
        print(f"  Time range: {total_time:.2f}s")
        print("===============================================================\n")

    return buf.getvalue()

def process_output(filename: str, **kwargs):
    df = pd.read_csv(filename)
    summary_str = ProcessSummary(df, pending_queries=0)

    filename_without_parent_or_ext = os.path.splitext(os.path.basename(filename))[0]
    timestamp = datetime.now().strftime("%Y%m%d-%H%M")
    results_path = f"4-latest-results/{filename_without_parent_or_ext}-{timestamp}.results"

    # Read bench-spec.yaml and filter out lines with hf_token
    bench_spec_content = ""
    if os.path.exists("bench-spec.yaml"):
        with open("bench-spec.yaml", "r") as spec_file:
            bench_spec_content = "".join(
                line for line in spec_file if "hf_token" not in line
            )
    else:
        print("bench-spec.yaml not found")

    with open(results_path, "w") as f:
        # Write the timestamp
        f.write(f"Timestamp: {timestamp}\n")
        # Write the summary statistics
        f.write(summary_str)
        # Write the specific workload for this set of statistics
        f.write("\n==================== Workload config ======================\n")
        for k, v in kwargs.items():
            f.write(f"{k}: {v}\n")
        f.write("===========================================================\n")
        # Write the bench-spec.yaml content
        if bench_spec_content:
            f.write("\n==================== bench-spec.yaml ======================\n")
            f.write(bench_spec_content)
            f.write("\n===========================================================\n")

    print(f"Performance summary saved to {results_path}")

    # Save a copy of the results file to ~/srv/runner-db/
    runner_db_path = os.path.expanduser("~/srv/runner-db/")
    os.makedirs(runner_db_path, exist_ok=True)
    runner_db_file = os.path.join(runner_db_path, f"{filename_without_parent_or_ext}-{timestamp}.results")

    # Copy the contents to the new location
    with open(results_path, "r") as src, open(runner_db_file, "w") as dst:
        dst.write(src.read())

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python summarize.py <path_to_csv> [key=value ...]")
        sys.exit(1)

    filename = sys.argv[1]
    raw_kwargs = sys.argv[2:]

    def parse_value(val):
        try:
            return eval(val, {}, {})
        except:
            return val

    kwargs = {}
    for arg in raw_kwargs:
        if "=" in arg:
            key, val = arg.split("=", 1)
            kwargs[key] = parse_value(val)

    process_output(filename, **kwargs)
