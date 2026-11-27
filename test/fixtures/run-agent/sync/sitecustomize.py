# Loaded through PYTHONPATH. Holds each `jobs.py write` right after its first look at the job folder until three
# writers have looked (8 s at most), so all three choose a job id from the same view of the folder.
import os, select, sys
_real, _held = os.listdir, []


def _listdir(path="."):
    names = _real(path)
    d = os.environ.get("RA_SYNC_DIR")
    if d and not _held and os.path.basename(sys.argv[0]) == "jobs.py" and sys.argv[1:2] == ["write"] \
            and os.path.basename(os.fspath(path)) == "jobs":
        _held.append(1)
        go = os.open(os.environ["RA_SYNC_GO"], os.O_RDWR)   # a FIFO, open before the marker says "I looked"
        open(os.path.join(d, str(os.getpid())), "w").close()
        if len(_real(d)) >= 3:
            os.write(go, b"xxx")
        if select.select([go], [], [], 8)[0]:
            os.read(go, 1)
    return names


os.listdir = _listdir
