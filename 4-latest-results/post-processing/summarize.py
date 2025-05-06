import pandas as pd
import sys
from typing import Optional
import os
import io
import contextlib

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
        print(f"  QPS: {qps:.4f} reqs/s")
        print(f"  Processing speed: {finished_qps:.4f} reqs/s")
        print(f"  Requests on-the-fly: {pending_queries}")
        print(f"  Input tokens per second: {average_prefill_speed:.4f} tokens/s")
        print(f"  Output tokens per second: {average_generation_speed:.4f} tokens/s")
        print(f"  Average generation throughput (per request): {average_generation_speed_per_request:.4f} tokens/req/s")
        print(f"  Average TTFT: {average_ttft:.4f}s")
        print(f"  Average generation_time / generation_tokens (Inter-Token Latency): {average_ratio:.4f}")
        print(f"  Time range: {start_time} - {end_time} ({total_time:.2f}s)")
        print("===============================================================\n")

    return buf.getvalue()

def process_output(filename: str):
    df = pd.read_csv(filename)
    summary_str = ProcessSummary(df, pending_queries=0)

    filename_without_parent_or_ext = os.path.splitext(os.path.basename(filename))[0]
    results_path = f"4-latest-results/ttft-itl-{filename_without_parent_or_ext}.results"

    with open(results_path, "w") as f:
        f.write(summary_str)

    print(f"Performance summary saved to {results_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python summarize.py <path_to_csv>")
        sys.exit(1)
    process_output(sys.argv[1])
