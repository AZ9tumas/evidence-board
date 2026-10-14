#!/usr/bin/env python3
"""Downloads the screenshots the Snapshot workflow published for a commit.

Usage: Tools/fetch-snapshots.py <commit-sha> <output-dir>

The workflow stores each JPEG as base64 in the text of neutral check runs named
"snapshot img<n> part<i>/<total>". This reassembles them into <output-dir>/shot<n>.jpg.
"""
import base64
import collections
import json
import os
import re
import sys
import urllib.request

sha, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
url = f"https://api.github.com/repos/AZ9tumas/evidence-board/commits/{sha}/check-runs?per_page=100"
runs = json.load(urllib.request.urlopen(url))["check_runs"]
parts = collections.defaultdict(dict)
for r in runs:
    m = re.match(r"snapshot img(\d+) part(\d+)/(\d+)", r["name"])
    if m:
        parts[int(m[1])][int(m[2])] = r["output"]["text"]
for n, chunks in sorted(parts.items()):
    data = base64.b64decode("".join(chunks[i] for i in sorted(chunks)))
    path = os.path.join(out, f"shot{n}.jpg")
    with open(path, "wb") as f:
        f.write(data)
    print(path, len(data))
