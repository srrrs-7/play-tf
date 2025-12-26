#!/usr/bin/env python3
"""
Sample ECS Job Script

This script demonstrates a typical batch job pattern:
1. Read configuration from environment variables
2. Perform some processing
3. Output results to stdout (captured by CloudWatch Logs)

Environment Variables:
    JOB_NAME: Name of the job (optional)
    PROCESS_COUNT: Number of items to process (optional, default: 5)
"""

import os
import sys
import time
import json
from datetime import datetime


def main():
    job_name = os.environ.get('JOB_NAME', 'sample-job')
    process_count = int(os.environ.get('PROCESS_COUNT', '5'))

    print(f"{'='*60}")
    print(f"ECS Job Started: {job_name}")
    print(f"Start Time: {datetime.now().isoformat()}")
    print(f"Process Count: {process_count}")
    print(f"{'='*60}")

    # Simulate processing
    results = []
    for i in range(1, process_count + 1):
        print(f"Processing item {i}/{process_count}...")
        time.sleep(1)  # Simulate work

        result = {
            "item_id": i,
            "status": "completed",
            "processed_at": datetime.now().isoformat()
        }
        results.append(result)
        print(f"  -> Item {i} completed")

    # Output summary
    print(f"\n{'='*60}")
    print("Job Summary:")
    print(f"  Total Items: {process_count}")
    print(f"  Successful: {len(results)}")
    print(f"  Failed: 0")
    print(f"  End Time: {datetime.now().isoformat()}")
    print(f"{'='*60}")

    # Output results as JSON (useful for downstream processing)
    print("\nResults JSON:")
    print(json.dumps({
        "job_name": job_name,
        "status": "success",
        "results": results
    }, indent=2))

    return 0


if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
