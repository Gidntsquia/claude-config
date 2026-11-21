#!/usr/bin/env python3
"""proc.py: look up other processes on Linux (/proc) and macOS (sysctl and ps, no /proc there).

Used by run-agent.sh, runner.sh, jobs.py and launch.py. Standard library only.
  proc.py from-agent          the --agent name of the nearest parent claude, or nothing
  proc.py claude-under <pid>  exit 0 when a claude process runs below <pid>
  proc.py argv <pid>          one argument per line
"""
import ctypes
import os
import struct
import subprocess
import sys

LINUX = os.path.isdir("/proc/self")
SHELLS = ("bash", "sh", "zsh", "dash", "node")


def _procargs(pid):
    """macOS: (argv, environ) from sysctl kern.procargs2; ([], None) when it cannot be read"""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        mib = (ctypes.c_int * 3)(1, 49, int(pid))  # CTL_KERN, KERN_PROCARGS2
        size = ctypes.c_size_t(0)
        if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0 or size.value < 8:
            return [], None
        buf = ctypes.create_string_buffer(size.value)
        if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
            return [], None
        raw = buf.raw[:size.value]
        argc = struct.unpack("i", raw[:4])[0]
        rest = raw[4:]
        end = rest.find(b"\0")              # the executable path, then padding NULs
        rest = rest[end:].lstrip(b"\0")
        parts = rest.split(b"\0")
        args = parts[:argc]
        env = [p for p in parts[argc:] if p]
        # Apple's own binaries (/bin/bash) hide their environment: an empty list then means unknown
        return [a.decode(errors="replace") for a in args], (env or None)
    except (OSError, AttributeError, ValueError, struct.error):
        return [], None


def argv(pid):
    """the argument list of <pid>, [] when unknown"""
    if LINUX:
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
            return [a.decode(errors="replace") for a in raw if a]
        except OSError:
            return []
    return _procargs(pid)[0]


def environ(pid):
    """the environment of <pid> as a list of b"KEY=value", None when it cannot be read"""
    if LINUX:
        try:
            return [x for x in open(f"/proc/{pid}/environ", "rb").read().split(b"\0") if x]
        except OSError:
            return None
    return _procargs(pid)[1]


def ppid(pid):
    """the parent of <pid>, 0 when unknown"""
    try:
        if LINUX:
            return int(open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1])
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True).stdout
        return int(out.strip())
    except (OSError, ValueError, IndexError):
        return 0


def is_claude(args):
    """argv of a claude process: argv[0] is claude, or a shell/node running a file named claude"""
    if not args:
        return False
    if os.path.basename(args[0]) == "claude":
        return True
    return len(args) > 1 and os.path.basename(args[0]) in SHELLS and os.path.basename(args[1]) == "claude"


def test_made(pid):
    """test mode: was this claude started by test.sh? Its environment carries RUN_AGENT_TEST=1; where the
    environment cannot be read (macOS, Apple binaries), it counts when it runs below test.sh
    (RUN_AGENT_TEST_PID) or below a tmux server on one of the test's own sockets."""
    env = environ(pid)
    if env is not None:
        return b"RUN_AGENT_TEST=1" in env
    top = os.environ.get("RUN_AGENT_TEST_PID", "")
    tdir = os.environ.get("RUN_AGENT_TEST_DIR", "")
    p = ppid(pid)
    while p > 1:
        if top and str(p) == top:
            return True
        a = argv(p)
        if a and os.path.basename(a[0]).startswith("tmux"):
            for i, w in enumerate(a[:-1]):
                s = a[i + 1]
                if w == "-L" and s.startswith("run-agent-test"):
                    return True
                if w == "-S" and (os.path.basename(s).startswith("run-agent-test")
                                  or (tdir and os.path.realpath(s).startswith(os.path.realpath(tdir) + os.sep))):
                    return True
            return False
        p = ppid(p)
    return False


def parent_claude(test=False):
    """(pid, argv) of the nearest parent claude process; (0, []) when there is none.
    test=True: only a claude the test started counts, and the walk stops at test.sh itself."""
    top = os.environ.get("RUN_AGENT_TEST_PID", "") if test else ""
    pid = os.getppid()
    while pid > 1:
        if top and str(pid) == top:
            break
        a = argv(pid)
        if a and os.path.basename(a[0]) == "claude":
            if not test or test_made(pid):
                return pid, a
            break
        pid = ppid(pid)
    return 0, []


def claude_under(root):
    """does a claude process run below <root>?"""
    kids = {}
    if LINUX:
        for n in os.listdir("/proc"):
            if n.isdigit():
                try:
                    st = open(f"/proc/{n}/stat").read().rsplit(")", 1)[1].split()
                    kids.setdefault(st[1], []).append(n)
                except (OSError, IndexError):
                    pass
    else:
        out = subprocess.run(["ps", "-Ao", "pid=,ppid="], capture_output=True, text=True).stdout
        for line in out.splitlines():
            f = line.split()
            if len(f) == 2:
                kids.setdefault(f[1], []).append(f[0])
    todo = [str(root)]
    while todo:
        p = todo.pop()
        for c in kids.get(p, []):
            if LINUX:
                try:
                    if open(f"/proc/{c}/comm").read().strip() == "claude":
                        return True
                except OSError:
                    pass
            elif is_claude(argv(c)):
                return True
            todo.append(c)
    return False


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "from-agent":
        _, a = parent_claude(test=os.environ.get("RUN_AGENT_TEST") == "1")
        if "--agent" in a[:-1]:
            print(a[a.index("--agent") + 1])
    elif cmd == "claude-under":
        sys.exit(0 if claude_under(sys.argv[2]) else 1)
    elif cmd == "argv":
        print("\n".join(argv(sys.argv[2])))
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
