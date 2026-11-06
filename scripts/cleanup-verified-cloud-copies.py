"""Remove only local, untracked conflict copies proven equal to a GitHub blob.

Cloud-only, changed, unbacked and ambiguous files are preserved. The two
allowed folders contain this task's synthetic evidence and test sources.
No build caches, simulator data, cloud settings or other projects are touched.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--delete", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
os.chdir(repo)
git = lambda *a: subprocess.check_output(["git", *a])
revision = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
assert revision == git("rev-parse", "HEAD").decode().strip(), "Back up current work before cleanup"
entries = {}
for row in git("ls-tree", "-r", "-z", revision, "--", "Design/native/health-write-order", "Tests").split(b"\0"):
    if row:
        metadata, name = row.split(b"\t", 1)
        mode, kind, oid = metadata.split()
        if mode in {b"100644", b"100755"} and kind == b"blob":
            entries[name.decode()] = oid.decode()
tracked = {p.decode() for p in git("ls-files", "-z").split(b"\0") if p}
folders = [Path("Design/native/health-write-order"), Path("Tests")]
assert all(p.is_dir() and not p.is_symlink() for p in folders)
candidates = sorted(p for folder in folders for p in folder.iterdir() if " 2." in p.name)
quarantine = Path(tempfile.mkdtemp(prefix="LumenVerifiedCloudCopies-")) if args.delete else None
before = shutil.disk_usage(repo).free
deleted, matched, skipped, retained = [], [], [], []


def identity(s):
    return s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns


def read_local(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_flags & 0x40000000:
        return None, info
    if info.st_size > 32 * 1024 * 1024:
        return None, info
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        assert identity(os.fstat(fd)) == identity(info)
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(info.st_size + 1)
        assert identity(os.fstat(fd)) == identity(info) and len(data) == info.st_size
        return data, info
    finally:
        os.close(fd)


with subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE) as reader:
    for index, path in enumerate(candidates):
        canonical = str(path.with_name(path.name.replace(" 2.", ".", 1)))
        if str(path) in tracked or canonical not in entries:
            skipped.append({"path": str(path), "reason": "tracked or no regular backed-up canonical blob"})
            continue
        try:
            data, info = read_local(path)
            if data is None:
                skipped.append({"path": str(path), "reason": "cloud-only, nonregular, hardlinked or over32MiB"})
                continue
            oid = entries[canonical]
            calculated = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
            if calculated != oid:
                skipped.append({"path": str(path), "reason": "different content; preserved"})
                continue
            reader.stdin.write((oid + "\n").encode()); reader.stdin.flush()
            header = reader.stdout.readline().split()
            assert header[0].decode() == oid and header[1] == b"blob"
            original = reader.stdout.read(int(header[2]))
            assert reader.stdout.read(1) == b"\n" and original == data
            record = {"path": str(path), "canonical": canonical, "gitBlob": oid,
                      "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                      "allocatedBytes": info.st_blocks * 512, "inode": info.st_ino}
            matched.append(record)
            if not args.delete:
                continue
            assert identity(path.lstat()) == identity(info)
            owned = quarantine / str(index)
            path.rename(owned)
            # Inspect the moved file again, so a pathname replacement cannot
            # cause an unverified copy to be deleted.
            moved, moved_info = read_local(owned)
            if moved != original or identity(moved_info) != identity(info):
                if not path.exists() and not path.is_symlink():
                    owned.rename(path)
                else:
                    retained.append(str(owned))
                skipped.append({"path": str(path), "reason": "changed during quarantine; preserved"})
                continue
            owned.unlink()
            deleted.append(record)
            if len(deleted) % 500 == 0:
                print("Verified copies removed:", len(deleted), flush=True)
        except (OSError, AssertionError) as error:
            skipped.append({"path": str(path), "reason": type(error).__name__ + "; preserved remaining data"})
    reader.stdin.close()
    reader.wait(timeout=10)
after = shutil.disk_usage(repo).free
if quarantine is not None:
    if not any(quarantine.iterdir()):
        quarantine.rmdir()
    else:
        retained.append(str(quarantine))
result = {"status": "completed scoped verified-copy cleanup" if args.delete else "dry run; no deletion",
          "checkedAt": time.time(), "remoteMain": revision, "deleteRequested": args.delete,
          "scriptSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          "candidateCount": len(candidates), "matchedCount": len(matched), "deletedCount": len(deleted),
          "logicalBytesRemoved": sum(r["bytes"] for r in deleted),
          "allocatedBytesRemoved": sum(r["allocatedBytes"] for r in deleted),
          "availableBytesBefore": before, "availableBytesAfter": after, "availableBytesChange": after - before,
          "quarantinedDataRetained": retained,
          "scope": "Only local untracked copies byte-compared to exact GitHub-main blobs; cloud-only and mismatching copies preserved. Canonical inputs and live test/build caches untouched. Concurrent allocations can affect free-space change.",
          "recordsArchive": "cloud-conflict-copy-cleanup-r1-files.json.gz"}
output = repo / "Design/native/health-write-order"
with (output / result["recordsArchive"]).open("wb") as stream:
    with gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as compressed:
        compressed.write(json.dumps({"deleted": deleted, "skipped": skipped}, sort_keys=True).encode())
(output / "cloud-conflict-copy-cleanup-r1.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2), flush=True)
