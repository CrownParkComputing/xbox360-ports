#!/usr/bin/env python3
"""Frame-pacing stats from a rexglue run.log (uses the timestamped PRESENT lines).

  tools/framepacing.py games/hydrothunder/logs/run.log [label]

Reports median/percentile frame times and counts the hitches — a stutter shows up as a
long tail, not a lower average, so the average FPS alone will hide it.
"""
import sys, re
from datetime import datetime

path = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else path

ts = []
pat = re.compile(r'^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\].*PRESENT')
for line in open(path, errors='replace'):
    m = pat.match(line)
    if m:
        ts.append(datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S.%f'))

if len(ts) < 3:
    print(f'{label}: only {len(ts)} presents — nothing to measure')
    sys.exit(0)

d = sorted(((ts[i+1] - ts[i]).total_seconds() * 1000.0) for i in range(len(ts) - 1))
n = len(d)
def pct(p):
    return d[min(n - 1, int(n * p / 100))]

span = (ts[-1] - ts[0]).total_seconds()
print(f'=== {label} ===')
print(f'  presents      : {len(ts)} over {span:.1f}s  (mean {len(ts)/span:.1f} FPS)')
print(f'  frame time ms : p50={pct(50):.1f}  p90={pct(90):.1f}  p99={pct(99):.1f}  max={d[-1]:.1f}')
# Hitches: anything well past a 60Hz frame. These are what you *feel* as jitter.
for thr in (33, 50, 100, 250):
    c = sum(1 for x in d if x > thr)
    print(f'  >{thr:>3}ms hitches: {c:5d}  ({100.0*c/n:5.2f}% of frames)')
