#!/usr/bin/env python3
"""Compare a legacy app's secrets against everything else, by hash only.

For each key in the app's legacy Vault blobs (kv/<meta-id>/<env>/secrets, key CREDS),
print its hash and where the same value already lives: ghostmind/global/*,
ghostmind/project/*, other projects' legacy blobs, and local .env.* files.
Values are never printed.

  compare-secrets.py <meta-id> [--local <dir>]...

Read the output as:
  - matches in ghostmind/global          -> point to that global key
  - matches in another project's blobs    -> shared across products: candidate for global
  - matches only in this project          -> project-scoped (one path, not duplicates)
  - '${' flag                             -> the legacy value interpolates; resolve it first
  - local file matches                    -> the local file is safe to delete
"""
import hashlib
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

POOL = ThreadPoolExecutor(max_workers=24)


def vault_json(*args):
    # vault wants flags before positional args: `vault kv get -format=json <path>`
    *cmd, path = args
    out = subprocess.run(["vault", *cmd, "-format=json", path], capture_output=True, text=True)
    return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else None


def kv_list(path):
    return vault_json("kv", "list", path) or []


def kv_data(path):
    d = vault_json("kv", "get", path)
    return (d or {}).get("data", {}).get("data", {}) or {}


def normalize(v):
    # what compose env_file did: trim, then strip one pair of matching quotes
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v


def parse_dotenv(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$", line)
        if m:
            out[m.group(1)] = normalize(m.group(2))
    return out


def h(v):
    return hashlib.sha256(v.encode()).hexdigest()[:8]


def walk_ghostmind(prefix, index):
    paths, frontier = [], [prefix]
    while frontier:
        listings = list(POOL.map(kv_list, frontier))
        nxt = []
        for parent, entries in zip(frontier, listings):
            for entry in entries:
                path = parent.rstrip("/") + "/" + entry.rstrip("/")
                paths.append(path)
                if entry.endswith("/"):
                    nxt.append(path)
        frontier = nxt
    for path, data in zip(paths, POOL.map(kv_data, paths)):
        for k, v in data.items():
            if isinstance(v, str) and v:
                index.setdefault(h(normalize(v)), []).append(f"{path}#{k}")


def legacy_blobs(meta_id):
    envs = [e.rstrip("/") for e in kv_list(f"kv/{meta_id}")]
    datas = POOL.map(kv_data, [f"kv/{meta_id}/{e}/secrets" for e in envs])
    return {e: parse_dotenv(d["CREDS"]) for e, d in zip(envs, datas) if d.get("CREDS")}


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__)
        sys.exit(1)
    meta_id, local_dirs = args[0], []
    for i, a in enumerate(args):
        if a == "--local" and i + 1 < len(args):
            local_dirs.append(args[i + 1])

    index = {}
    walk_ghostmind("ghostmind/global", index)
    walk_ghostmind("ghostmind/project", index)
    # flat, one level of pool work at a time (a worker waiting on the same pool deadlocks)
    others = [o.rstrip("/") for o in kv_list("kv") if o.rstrip("/") != meta_id]
    env_lists = list(POOL.map(kv_list, [f"kv/{o}" for o in others]))
    pairs = [(o, e.rstrip("/")) for o, envs in zip(others, env_lists) for e in envs]
    datas = POOL.map(kv_data, [f"kv/{o}/{e}/secrets" for o, e in pairs])
    for (other, env), d in zip(pairs, datas):
        if not d.get("CREDS"):
            continue
        for k, v in parse_dotenv(d["CREDS"]).items():
            if v:
                index.setdefault(h(v), []).append(f"kv/{other}/{env}#{k}")
    for d in local_dirs:
        for f in Path(d).rglob(".env*"):
            if f.is_file() and "node_modules" not in f.parts:
                for k, v in parse_dotenv(f.read_text(errors="ignore")).items():
                    if v:
                        index.setdefault(h(v), []).append(f"local:{f}#{k}")

    for env, kvs in sorted(legacy_blobs(meta_id).items()):
        print(f"\n== kv/{meta_id}/{env}")
        for k, v in sorted(kvs.items()):
            if not v:
                print(f"  {k:40} (empty)")
                continue
            flag = " ${" if "${" in v else ""
            where = list(dict.fromkeys(index.get(h(v), [])))
            print(f"  {k:40} {h(v)}{flag}  {', '.join(where) if where else '-'}")


if __name__ == "__main__":
    main()
