#!/usr/bin/env python3
"""Scan a pinned Quicklisp-format distribution.

sweep.sh stays the 18-project smoke corpus. This script downloads a
releases.txt snapshot, checks the file md5 and the content sha1, extracts,
and scans every tree in one SBCL process. One project failing does not stop
the run. The committed
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
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parent
BATCH = ROOT / "bin" / "corpus-batch.lisp"
PROFILES = ROOT / "profiles"


# quicklisp-controller skips these directories when it hashes member bytes.
IGNORED_CONTENT_DIRS = ("/_darcs/", "/CVS/", "/.git/", "/.hg/")


def file_digest(path, algo):
    digest = hashlib.new(algo)
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def md5_file(path):
    return file_digest(path, "md5")


def content_sha1(path, mode):
    """SHA1 of the archive's file bytes.

    The releases.txt column is content-sha1, not the sha1 of the gzip.
    Quicklisp sorts regular files by name and skips VCS directories.
    Ultralisp hashes GNU tar -xO output, which is archive order.
    """
    if mode == "ultralisp":
        proc = subprocess.Popen(
            ["tar", "-xOzf", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        digest = hashlib.sha1()
        assert proc.stdout is not None
        for chunk in iter(lambda: proc.stdout.read(1 << 20), b""):
            digest.update(chunk)
        stderr = proc.stderr.read() if proc.stderr is not None else b""
        if proc.wait() != 0:
            raise OSError(stderr.decode("utf-8", "replace")[:200])
        return digest.hexdigest()
    if mode != "quicklisp":
        raise ValueError(f"unknown content-sha1 mode {mode}")
    digest = hashlib.sha1()
    members = []
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isreg():
                continue
            if any(piece in member.name for piece in IGNORED_CONTENT_DIRS):
                continue
            members.append(member)
        members.sort(key=lambda member: member.name)
        for member in members:
            extracted = archive.extractfile(member)
            digest.update(extracted.read() if extracted is not None else b"")
    return digest.hexdigest()


def classify_archive(path, row, mode):
    """Return how PATH compares with ROW.

    ok: file md5 and content-sha1 both match.
    legacy: file md5 matches, but Quicklisp's published content-sha1 does not
    equal the member hash. Some older release rows predate the current
    hasher, so that is not a corrupt download.
    sha: Ultralisp content-sha1 does not match. The download is rejected.
    md5: the gzip md5 does not match.
    """
    if md5_file(path) != row["md5"]:
        return "md5"
    if content_sha1(path, mode) == row["sha1"]:
        return "ok"
    if mode == "quicklisp":
        return "legacy"
    return "sha"


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


def download_one(row, tarball_dir, content_mode):
    dest = tarball_dir / f"{row['prefix']}.tgz"
    try:
        if dest.is_file():
            status = classify_archive(dest, row, content_mode)
            if status == "ok":
                return "have"
            if status == "legacy":
                return "legacy"
            if status == "sha":
                dest.unlink()
                return "fail"
    except (OSError, tarfile.TarError):
        return "fail"
    part = dest.with_suffix(".tgz.part")
    result = subprocess.run(
        ["curl", "-fsSL", "--retry", "3", "--retry-delay", "1", "-o", str(part), row["url"]],
        capture_output=True,
    )
    if result.returncode != 0 or not part.exists():
        part.unlink(missing_ok=True)
        return "fail"
    try:
        status = classify_archive(part, row, content_mode)
    except (OSError, tarfile.TarError):
        part.unlink(missing_ok=True)
        return "fail"
    if status in ("md5", "sha"):
        part.unlink(missing_ok=True)
        return "fail"
    part.replace(dest)
    return "legacy" if status == "legacy" else "ok"


def extract_marker(src_root, prefix):
    return src_root.parent / "extracted" / prefix


def extract_one(row, tarball_dir, src_root):
    """Extract ROW into src_root / prefix.

    A nonempty directory is not enough. The extract is written in a temporary
    directory and renamed into place, and a marker records the archive md5 and
    sha1. A rerun trusts the directory only when that marker matches.
    """
    dest = src_root / row["prefix"]
    marker = extract_marker(src_root, row["prefix"])
    expected = f"{row['md5']} {row['sha1']}\n"
    try:
        if dest.is_dir() and marker.is_file() and marker.read_text(encoding="utf-8") == expected:
            return "have"
    except OSError:
        pass
    archive = tarball_dir / f"{row['prefix']}.tgz"
    if not archive.is_file():
        return "fail"
    tmp_root = src_root.parent / "partial" / f"{row['prefix']}.{os.getpid()}.{threading.get_ident()}"
    try:
        if tmp_root.exists():
            shutil.rmtree(tmp_root)
        tmp_root.mkdir(parents=True)
        result = subprocess.run(
            ["tar", "-xzf", str(archive), "-C", str(tmp_root)],
            capture_output=True,
        )
        extracted = tmp_root / row["prefix"]
        if result.returncode != 0 or not extracted.is_dir():
            return "fail"
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        extracted.rename(dest)
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(expected, encoding="utf-8")
        return "ok"
    except OSError:
        return "fail"
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


def run_pool(rows, workers, fn):
    counts = {"ok": 0, "have": 0, "legacy": 0, "fail": 0}
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
                    f"progress {done} ok={counts['ok']} have={counts['have']} "
                    f"legacy={counts['legacy']} fail={counts['fail']}",
                    flush=True,
                )
    return counts, failed


def norm(text):
    return " ".join((text or "").lower().split())


def fingerprint(finding):
    """Guard chain plus the whole-form hash.

    feature and suggestion stay in the identity so two different typo
    suggestions do not collapse. preview is display text and is not hashed.
    """
    chain = [norm(item) for item in finding.get("parent_guards") or []]
    chain.append(norm(finding.get("guard")))
    return "|".join(
        [
            finding.get("kind") or "",
            finding.get("feature") or "",
            finding.get("suggestion") or "",
            " >> ".join(chain),
            finding.get("form_hash") or "",
        ]
    )


def aggregate(jsonl_path):
    groups = {}
    failures = []
    failed_names = set()
    scanned_projects = set()
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
            name = obj.get("project")
            if obj.get("error"):
                failures.append({"project": name, "error": obj["error"][:500]})
                failed_names.add(name)
                scanned_projects.discard(name)
                continue
            if name not in failed_names:
                scanned_projects.add(name)
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
                        "form_hash": finding.get("form_hash"),
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
        "scanned_projects": sorted(scanned_projects),
        "findings": findings,
    }


def account_rows(rows, download_failed, extract_failed, summary):
    """Every release row is scanned or failed.

    Download and extract failures never reach scan.jsonl, so the scan summary
    alone can report failed=0 while a project is missing. A project that is
    in none of the three failure sets and was not scanned is recorded too.
    """
    download_set = set(download_failed)
    extract_set = set(extract_failed)
    scan_errors = {}
    for item in summary.get("failures") or []:
        scan_errors.setdefault(item.get("project"), item.get("error") or "scan failed")
    success = set(summary.get("scanned_projects") or [])
    records = []
    scanned = 0
    for row in rows:
        name = row["project"]
        if name in download_set:
            records.append({"project": name, "stage": "download", "error": "download failed"})
        elif name in extract_set:
            records.append({"project": name, "stage": "extract", "error": "extract failed"})
        elif name in scan_errors:
            records.append({"project": name, "stage": "scan", "error": scan_errors[name]})
        elif name in success:
            scanned += 1
        else:
            records.append({"project": name, "stage": "missing", "error": "not scanned"})
    failed = len(records)
    if scanned + failed != len(rows):
        raise SystemExit(
            f"project accounting failed: scanned={scanned} failed={failed} projects={len(rows)}"
        )
    return scanned, failed, records


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


def self_test_extract():
    """A nonempty directory without a matching marker is extracted again."""
    with tempfile.TemporaryDirectory(prefix="skiptrace-extract-") as tmp:
        root = Path(tmp)
        src = root / "src"
        tarballs = root / "tarballs"
        build = root / "build" / "sample-1.0"
        src.mkdir()
        tarballs.mkdir()
        (build / "sub").mkdir(parents=True)
        (build / "a.lisp").write_text(";; a\n", encoding="utf-8")
        (build / "sub" / "b.lisp").write_text(";; b\n", encoding="utf-8")
        archive = tarballs / "sample-1.0.tgz"
        result = subprocess.run(
            ["tar", "-czf", str(archive), "-C", str(root / "build"), "sample-1.0"],
            capture_output=True,
        )
        if result.returncode != 0:
            print("SELF_TEST_FAIL could not build the sample archive", file=sys.stderr)
            return False
        data = archive.read_bytes()
        row = {
            "project": "sample",
            "prefix": "sample-1.0",
            "md5": hashlib.md5(data).hexdigest(),
            "sha1": hashlib.sha1(data).hexdigest(),
        }
        if extract_one(row, tarballs, src) != "ok":
            print("SELF_TEST_FAIL first extract", file=sys.stderr)
            return False
        kept = src / "sample-1.0" / "sub" / "b.lisp"
        kept.unlink()
        extract_marker(src, "sample-1.0").unlink()
        if extract_one(row, tarballs, src) != "ok" or not kept.is_file():
            print("SELF_TEST_FAIL partial extract was trusted", file=sys.stderr)
            return False
        if extract_one(row, tarballs, src) != "have":
            print("SELF_TEST_FAIL marked extract was repeated", file=sys.stderr)
            return False
    return True


def self_test_account():
    """A download failure counts even when the scan summary says failed=0."""
    rows = [{"project": "a"}, {"project": "b"}, {"project": "c"}]
    summary = {"failed": 0, "failures": [], "scanned_projects": ["a", "b"]}
    scanned, failed, records = account_rows(rows, ["c"], [], summary)
    if (scanned, failed) != (2, 1) or records[0]["stage"] != "download":
        print(f"SELF_TEST_FAIL account download scanned={scanned} failed={failed} {records}", file=sys.stderr)
        return False
    if summary["failed"] != 0 or scanned + failed != len(rows):
        print("SELF_TEST_FAIL account still trusts the scan summary", file=sys.stderr)
        return False
    rows = [{"project": "a"}, {"project": "b"}, {"project": "d"}, {"project": "e"}]
    summary = {
        "failures": [{"project": "b", "error": "boom"}],
        "scanned_projects": ["a"],
    }
    scanned, failed, records = account_rows(rows, [], ["d"], summary)
    stages = {item["project"]: item["stage"] for item in records}
    if (scanned, failed) != (1, 3) or stages != {"b": "scan", "d": "extract", "e": "missing"}:
        print(f"SELF_TEST_FAIL account union scanned={scanned} failed={failed} {records}", file=sys.stderr)
        return False
    return True


def self_test_content_sha1():
    """Quicklisp and Ultralisp do not hash the gzip, and they do not hash alike."""
    with tempfile.TemporaryDirectory(prefix="skiptrace-sha1-") as tmp:
        archive = Path(tmp) / "sample.tgz"
        with tarfile.open(archive, "w:gz") as handle:
            for name, payload in (("b.txt", b"b"), ("a.txt", b"a"), ("pkg/.git/config", b"secret")):
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                handle.addfile(info, io.BytesIO(payload))
        md5 = md5_file(archive)
        quicklisp = hashlib.sha1(b"a" + b"b").hexdigest()
        ultralisp = hashlib.sha1(b"b" + b"a" + b"secret").hexdigest()
        row = {"md5": md5, "sha1": quicklisp}
        if classify_archive(archive, row, "quicklisp") != "ok":
            print("SELF_TEST_FAIL quicklisp rejected its own content-sha1", file=sys.stderr)
            return False
        if classify_archive(archive, {"md5": md5, "sha1": ultralisp}, "quicklisp") != "legacy":
            print("SELF_TEST_FAIL quicklisp treated a different content-sha1 as ok", file=sys.stderr)
            return False
        if classify_archive(archive, {"md5": "0" * 32, "sha1": quicklisp}, "quicklisp") != "md5":
            print("SELF_TEST_FAIL a wrong md5 was accepted", file=sys.stderr)
            return False
        if classify_archive(archive, {"md5": md5, "sha1": ultralisp}, "ultralisp") != "ok":
            print("SELF_TEST_FAIL ultralisp rejected its own content-sha1", file=sys.stderr)
            return False
        if classify_archive(archive, row, "ultralisp") != "sha":
            print("SELF_TEST_FAIL ultralisp accepted the Quicklisp content-sha1", file=sys.stderr)
            return False
    return True


def self_test():
    source = "#+sbcl\n(defun fast-path ()\n  #+ccl (ccl::%fast-thing)\n  :slow)\n"
    pad = "x" * 70
    long_alpha = f"#+sbcl\n#+ccl (widget {pad} alpha)\n"
    long_beta = f"#+sbcl\n#+ccl (widget {pad} beta)\n"
    if not self_test_account() or not self_test_content_sha1() or not self_test_extract():
        return 1
    with tempfile.TemporaryDirectory(prefix="skiptrace-corpus-") as tmp:
        root = Path(tmp)
        files = {
            "one": source,
            "two": source,
            "long-alpha": long_alpha,
            "long-beta": long_beta,
        }
        jobs = []
        for name, text in files.items():
            directory = root / name
            directory.mkdir()
            (directory / "a.lisp").write_text(text, encoding="utf-8")
            jobs.append((name, directory))
        jobs.append(("missing", root / "no-such"))
        jobs_path = root / "jobs.tsv"
        out_path = root / "out.jsonl"
        with jobs_path.open("w", encoding="utf-8") as handle:
            for name, directory in jobs:
                handle.write(f"{name}\t{directory}\n")
        scan_jobs(jobs_path, out_path)
        summary = aggregate(out_path)
        contradictions = [item for item in summary["findings"] if item["kind"] == "contradiction"]
        copied = [item for item in contradictions if item["occurrences"] == 2]
        distinct = [item for item in contradictions if item["occurrences"] == 1]
        if len(copied) != 1 or len(distinct) != 2:
            print(
                f"SELF_TEST_FAIL copied={len(copied)} distinct={len(distinct)} total={len(contradictions)}",
                file=sys.stderr,
            )
            return 1
        if distinct[0].get("form_hash") == distinct[1].get("form_hash"):
            print("SELF_TEST_FAIL different forms shared a hash", file=sys.stderr)
            return 1
        if distinct[0].get("preview") != distinct[1].get("preview"):
            print("SELF_TEST_FAIL the preview fixture no longer shares a first line", file=sys.stderr)
            return 1
        if summary["failed"] != 1 or summary["failures"][0]["project"] != "missing":
            print(f"SELF_TEST_FAIL failures={summary['failures']}", file=sys.stderr)
            return 1
        if summary["scanned"] != 4:
            print(f"SELF_TEST_FAIL scanned={summary['scanned']}", file=sys.stderr)
            return 1
    print(
        "self-test ok: 2 copies are 1 finding; 2 forms with the same preview stay distinct; "
        "a partial extract is redone; 1 project failure did not stop the run; "
        "a download failure is counted; content-sha1 follows the dist"
    )
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
    if args.source not in ("quicklisp", "ultralisp"):
        parser.error("--source must be quicklisp or ultralisp")
    print(f"projects {len(rows)}", flush=True)
    print("download", flush=True)
    download_counts, download_failed = run_pool(
        rows, args.workers, lambda row: download_one(row, tarball_dir, args.source)
    )
    print(
        f"DOWNLOAD_DONE ok={download_counts['ok']} have={download_counts['have']} "
        f"legacy={download_counts['legacy']} fail={download_counts['fail']}",
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
    scanned, failed, records = account_rows(rows, download_failed, extract_failed, summary)
    summary["scanned"] = scanned
    summary["failed"] = failed
    summary["failures"] = records
    failed_names = {item["project"] for item in records}
    statuses = {}
    for row in rows:
        statuses[row["project"]] = "failed" if row["project"] in failed_names else "scanned"
    releases_url = args.releases_url or str(releases_path)
    write_evidence(args.evidence, args.source, args.dist, releases_url, rows, statuses, summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
