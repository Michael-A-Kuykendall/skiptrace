#!/usr/bin/env python3
"""Scan a pinned Quicklisp-format distribution.

sweep.sh stays the 18-project smoke corpus. This script downloads a
releases.txt snapshot, checks md5, extracts, and scans every tree in one
SBCL process. One project failing does not stop the run. The committed
evidence is a manifest plus a deduplicated contradiction and typo summary.
Tarballs and per-project output stay in the cache directory, which is
gitignored when it lives under corpus/.

  python3 corpus-scan.py --self-test
  python3 corpus-scan.py \\
      --cache corpus/ql-2026-01-01 \\
      --releases corpus/ql-2026-01-01/releases.txt \\
      --releases-url https://beta.quicklisp.org/dist/quicklisp/2026-01-01/releases.txt \\
      --source quicklisp --dist 2026-01-01 \\
      --evidence evidence/quicklisp-2026-01-01
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parent
BATCH = ROOT / "bin" / "corpus-batch.lisp"
PROFILES = ROOT / "profiles"


def md5_file(path):
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_releases(text):
    rows = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        rows.append(
            {
                "project": parts[0],
                "url": parts[1],
                "size": parts[2],
                "md5": parts[3],
                "sha1": parts[4],
                "prefix": parts[5],
            }
        )
    return rows


def fetch_text(url):
    with urlopen(url, timeout=120) as response:
        return response.read().decode("utf-8", "replace")


def ensure_releases(path, url):
    path = Path(path) if path else None
    if path and path.is_file():
        return path.read_text(encoding="utf-8", errors="replace")
    if not url:
        raise SystemExit("need --releases or --releases-url")
    text = fetch_text(url)
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return text


def download_one(row, tarball_dir):
    dest = tarball_dir / f"{row['prefix']}.tgz"
    try:
        if dest.is_file() and md5_file(dest) == row["md5"]:
            return "have"
    except OSError:
        return "fail"
    part = dest.with_suffix(".tgz.part")
    result = subprocess.run(
        ["curl", "-fsSL", "--retry", "3", "--retry-delay", "1", "-o", str(part), row["url"]],
        capture_output=True,
    )
    if result.returncode != 0 or not part.exists():
        part.unlink(missing_ok=True)
        return "fail"
    if md5_file(part) != row["md5"]:
        part.unlink(missing_ok=True)
        return "fail"
    part.replace(dest)
    return "ok"


def extract_one(row, tarball_dir, src_root):
    dest = src_root / row["prefix"]
    if dest.is_dir() and any(dest.iterdir()):
        return "have"
    archive = tarball_dir / f"{row['prefix']}.tgz"
    if not archive.is_file():
        return "fail"
    dest.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["tar", "-xzf", str(archive), "-C", str(src_root)],
        capture_output=True,
    )
    if result.returncode != 0 or not dest.is_dir():
        return "fail"
    return "ok"


def run_pool(rows, workers, fn):
    counts = {"ok": 0, "have": 0, "fail": 0}
    failed = []
    with ThreadPoolExecutor(max(1, workers)) as pool:
        futures = {pool.submit(fn, row): row for row in rows}
        done = 0
        for future in as_completed(futures):
            done += 1
            row = futures[future]
            try:
                status = future.result()
            except Exception:
                status = "fail"
            counts[status] = counts.get(status, 0) + 1
            if status == "fail":
                failed.append(row["project"])
            if done % 200 == 0 or done == len(rows):
                print(
                    f"progress {done} ok={counts['ok']} have={counts['have']} fail={counts['fail']}",
                    flush=True,
                )
    return counts, failed


def norm(text):
    return " ".join((text or "").lower().split())


def fingerprint(finding):
    chain = [norm(item) for item in finding.get("parent_guards") or []]
    chain.append(norm(finding.get("guard")))
    return "|".join(
        [
            finding.get("kind") or "",
            finding.get("feature") or "",
            finding.get("suggestion") or "",
            " >> ".join(chain),
            norm(finding.get("preview")),
        ]
    )


def aggregate(jsonl_path):
    groups = {}
    failures = []
    files = 0
    forms = 0
    scanned = 0
    with open(jsonl_path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"bad json on line {number}: {exc}") from exc
            if obj.get("error"):
                failures.append({"project": obj.get("project"), "error": obj["error"][:500]})
                continue
            scanned += 1
            files += obj.get("files") or 0
            forms += obj.get("forms") or 0
            report = obj.get("report") or {}
            for finding in report.get("findings") or []:
                if finding.get("kind") not in ("contradiction", "likely-typo"):
                    continue
                key = fingerprint(finding)
                bucket = groups.get(key)
                if bucket is None:
                    bucket = {
                        "kind": finding.get("kind"),
                        "severity": finding.get("severity"),
                        "intentional": bool(finding.get("intentional")),
                        "guard": finding.get("guard"),
                        "parent_guards": finding.get("parent_guards") or [],
                        "preview": finding.get("preview"),
                        "feature": finding.get("feature"),
                        "suggestion": finding.get("suggestion"),
                        "occurrences": 0,
                        "sites": [],
                        "_projects": set(),
                    }
                    groups[key] = bucket
                else:
                    if not finding.get("intentional"):
                        bucket["intentional"] = False
                bucket["occurrences"] += 1
                bucket["_projects"].add(obj.get("project"))
                bucket["sites"].append(
                    {
                        "project": obj.get("project"),
                        "file": finding.get("file"),
                        "line": finding.get("line"),
                    }
                )
    findings = []
    for bucket in groups.values():
        bucket["projects"] = len(bucket.pop("_projects"))
        bucket["sites"].sort(key=lambda site: (site["project"] or "", site["file"] or "", site["line"] or 0))
        findings.append(bucket)
    findings.sort(
        key=lambda item: (
            -item["occurrences"],
            item["kind"] or "",
            item["guard"] or "",
            item["feature"] or "",
        )
    )
    return {
        "scanned": scanned,
        "failed": len(failures),
        "files": files,
        "guarded_forms": forms,
        "failures": failures,
        "findings": findings,
    }


def write_evidence(prefix, source, dist, releases_url, rows, statuses, summary):
    prefix = Path(prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    tsv_path = prefix.with_suffix(".tsv")
    json_path = prefix.with_suffix(".json")
    with tsv_path.open("w", encoding="utf-8") as handle:
        handle.write("source\tproject\turl\tsize\tmd5\tsha1\tprefix\tstatus\n")
        for row in rows:
            status = statuses.get(row["project"], "skipped")
            handle.write(
                "\t".join(
                    [
                        source,
                        row["project"],
                        row["url"],
                        row["size"],
                        row["md5"],
                        row["sha1"],
                        row["prefix"],
                        status,
                    ]
                )
                + "\n"
            )
    contradictions = [item for item in summary["findings"] if item["kind"] == "contradiction"]
    typos = [item for item in summary["findings"] if item["kind"] == "likely-typo"]
    body = {
        "source": source,
        "dist": dist,
        "releases": releases_url,
        "projects": len(rows),
        "scanned": summary["scanned"],
        "failed": summary["failed"],
        "files": summary["files"],
        "guarded_forms": summary["guarded_forms"],
        "contradiction_occurrences": sum(item["occurrences"] for item in contradictions),
        "contradiction_unique": len(contradictions),
        "typo_occurrences": sum(item["occurrences"] for item in typos),
        "typo_unique": len(typos),
        "failures": summary["failures"],
        "findings": summary["findings"],
    }
    json_path.write_text(json.dumps(body, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"evidence {json_path} projects={body['projects']} scanned={body['scanned']} "
        f"failed={body['failed']} contradictions={body['contradiction_occurrences']} "
        f"unique={body['contradiction_unique']} typos={body['typo_occurrences']} "
        f"typo_unique={body['typo_unique']}",
        flush=True,
    )
    return body


def scan_jobs(jobs_path, out_path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            "sbcl",
            "--script",
            str(BATCH),
            str(PROFILES),
            str(jobs_path),
            str(out_path),
        ]
    )
    if result.returncode != 0:
        raise SystemExit(f"corpus-batch exited {result.returncode}")


def self_test():
    source = "#+sbcl\n(defun fast-path ()\n  #+ccl (ccl::%fast-thing)\n  :slow)\n"
    with tempfile.TemporaryDirectory(prefix="skiptrace-corpus-") as tmp:
        root = Path(tmp)
        jobs = []
        for name in ("one", "two"):
            directory = root / name
            directory.mkdir()
            (directory / "a.lisp").write_text(source, encoding="utf-8")
            jobs.append((name, directory))
        missing = root / "no-such"
        jobs.append(("missing", missing))
        jobs_path = root / "jobs.tsv"
        out_path = root / "out.jsonl"
        with jobs_path.open("w", encoding="utf-8") as handle:
            for name, directory in jobs:
                handle.write(f"{name}\t{directory}\n")
        scan_jobs(jobs_path, out_path)
        summary = aggregate(out_path)
        contradictions = [item for item in summary["findings"] if item["kind"] == "contradiction"]
        if len(contradictions) != 1 or contradictions[0]["occurrences"] != 2:
            print(
                f"SELF_TEST_FAIL unique={len(contradictions)} "
                f"occurrences={contradictions[0]['occurrences'] if contradictions else 0}",
                file=sys.stderr,
            )
            return 1
        if summary["failed"] != 1 or summary["failures"][0]["project"] != "missing":
            print(f"SELF_TEST_FAIL failures={summary['failures']}", file=sys.stderr)
            return 1
        if summary["scanned"] != 2:
            print(f"SELF_TEST_FAIL scanned={summary['scanned']}", file=sys.stderr)
            return 1
    print("self-test ok: 2 occurrences of 1 unique contradiction; 1 project failure did not stop the run")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description="Scan a pinned Quicklisp-format distribution.")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--releases", type=Path)
    parser.add_argument("--releases-url", default="")
    parser.add_argument("--source", default="quicklisp")
    parser.add_argument("--dist", default="")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.cache or not args.evidence:
        parser.error("--cache and --evidence are required")
    cache = args.cache
    tarball_dir = cache / "tarballs"
    src_root = cache / "src"
    tarball_dir.mkdir(parents=True, exist_ok=True)
    src_root.mkdir(parents=True, exist_ok=True)
    releases_path = args.releases or (cache / "releases.txt")
    text = ensure_releases(releases_path, args.releases_url)
    rows = parse_releases(text)
    if not rows:
        raise SystemExit("releases.txt has no projects")
    print(f"projects {len(rows)}", flush=True)
    print("download", flush=True)
    download_counts, download_failed = run_pool(
        rows, args.workers, lambda row: download_one(row, tarball_dir)
    )
    print(
        f"DOWNLOAD_DONE ok={download_counts['ok']} have={download_counts['have']} fail={download_counts['fail']}",
        flush=True,
    )
    print("extract", flush=True)
    extract_counts, extract_failed = run_pool(
        rows, args.workers, lambda row: extract_one(row, tarball_dir, src_root)
    )
    print(
        f"EXTRACT_DONE ok={extract_counts['ok']} have={extract_counts['have']} fail={extract_counts['fail']}",
        flush=True,
    )
    failed_projects = set(download_failed) | set(extract_failed)
    jobs_path = cache / "jobs.tsv"
    ready = []
    with jobs_path.open("w", encoding="utf-8") as handle:
        for row in rows:
            directory = src_root / row["prefix"]
            if row["project"] in failed_projects or not directory.is_dir():
                continue
            ready.append(row)
            handle.write(f"{row['project']}\t{directory.resolve()}\n")
    print(f"scanning {len(ready)}", flush=True)
    out_path = cache / "scan.jsonl"
    scan_jobs(jobs_path, out_path)
    summary = aggregate(out_path)
    statuses = {}
    failed_names = {item["project"] for item in summary["failures"]}
    ready_names = {row["project"] for row in ready}
    for row in rows:
        if row["project"] in failed_projects or row["project"] in failed_names:
            statuses[row["project"]] = "failed"
        elif row["project"] in ready_names and row["project"] not in failed_names:
            statuses[row["project"]] = "scanned"
        else:
            statuses[row["project"]] = "skipped"
    releases_url = args.releases_url or str(releases_path)
    write_evidence(args.evidence, args.source, args.dist, releases_url, rows, statuses, summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
