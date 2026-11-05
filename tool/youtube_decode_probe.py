"""Decode complete test files, supplementing FFprobe and the packet-read scan."""
import json
import subprocess
import sys
import time

failed = False
for path in sys.argv[1:]:
    started = time.monotonic()
    result = subprocess.run([
        'ffmpeg', '-v', 'error', '-xerror', '-threads', '2', '-i', path,
        '-map', '0:v:0', '-map', '0:a:0', '-progress', 'pipe:1', '-f', 'null', '-',
    ], capture_output=True, text=True)
    progress = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    print(json.dumps({
        'path': path, 'exitCode': result.returncode,
        'status': 'VERIFIED' if result.returncode == 0 else 'FAILED',
        'frames': progress.get('frame'), 'decodedDuration': progress.get('out_time'),
        'elapsedSeconds': round(time.monotonic() - started, 3),
        'error': result.stderr.strip() or None,
    }), flush=True)
    failed = failed or result.returncode != 0
sys.exit(1 if failed else 0)
