#!/usr/bin/env python3
"""Phone picture of a page on macOS, drawn by the installed Firefox and no other browser, python3 stdlib only.
  phone-bidi.py <out-base> <url>
Starts Firefox headless as its own instance on a scratch profile and a free port (no window; the user's Firefox and
profile are not touched), drives it over WebDriver BiDi: viewport 390x844 css px, devicePixelRatio 2, the whole document.
A page up to one phone screen (844 css px) is <out-base>.png; a taller one is cut every 844 css px into
<out-base>-p1.png, -p2.png ...: each 780x1688, the last shorter. Prints "png <path> WxH" per part, exit 0.
Firefox missing, the port silent for 20 s, or BiDi answering with an error: prints ONE line
"phone-shot.sh: no picture: <reason>", exit 1, and leaves no file. The Firefox it started is killed before it exits.
PHONE_FIREFOX_APP=<Firefox.app> moves the lookup, PHONE_PORT_WAIT=<s> the 20 s, PHONE_SETTLE_MS the 500 ms after load,
PHONE_OVERLAY_SCROLLBARS=0 gives the page classic scroll bars (the test of the 375 px case).
"""
import base64, json, os, shutil, signal, socket, struct, subprocess, sys, tempfile, time

W, SCREEN, SCALE = 390, 844, 2


class Fail(Exception):
    pass


class WS:
    """The little of RFC 6455 that BiDi needs: text messages out (masked), text messages in (any size, fragments, pings)."""

    def __init__(self, port, path, timeout):
        self.s = socket.create_connection(('127.0.0.1', port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(('GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                        'Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n' % (path, port, key)).encode())
        self.buf = bytearray()
        while b'\r\n\r\n' not in self.buf:
            d = self.s.recv(4096)
            if not d: raise Fail('Firefox closed the connection during the handshake')
            self.buf += d
        head, _, rest = bytes(self.buf).partition(b'\r\n\r\n')
        self.buf = bytearray(rest)
        status = head.split(b'\r\n')[0].decode(errors='replace')
        if ' 101' not in status: raise Fail('the port answered "%s", not a websocket' % status)

    def _read(self, n):
        while len(self.buf) < n:
            d = self.s.recv(1 << 20)
            if not d: raise Fail('Firefox closed the connection')
            self.buf += d
        out = bytes(self.buf[:n]); del self.buf[:n]
        return out

    def _frame(self, op, data):
        n = len(data); mask = os.urandom(4)
        if n < 126: h = struct.pack('!BB', 0x80 | op, 0x80 | n)
        elif n < 65536: h = struct.pack('!BBH', 0x80 | op, 0x80 | 126, n)
        else: h = struct.pack('!BBQ', 0x80 | op, 0x80 | 127, n)
        self.s.sendall(h + mask + bytes(b ^ mask[i & 3] for i, b in enumerate(data)))

    def send(self, text):
        self._frame(1, text.encode())

    def recv(self):
        msg = bytearray()
        while True:
            b0, b1 = self._read(2)
            op, n = b0 & 0x0f, b1 & 0x7f
            if n == 126: n = struct.unpack('!H', self._read(2))[0]
            elif n == 127: n = struct.unpack('!Q', self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else None
            data = self._read(n)
            if mask: data = bytes(b ^ mask[i & 3] for i, b in enumerate(data))
            if op == 8: raise Fail('Firefox closed the connection')
            if op == 9: self._frame(10, data); continue
            if op == 10: continue
            msg += data
            if b0 & 0x80: return msg.decode('utf-8', errors='replace')


class Bidi:
    def __init__(self, ws):
        self.ws, self.n = ws, 0

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({'id': self.n, 'method': method, 'params': params}))
        while True:
            try:
                m = json.loads(self.ws.recv())
            except socket.timeout:
                raise Fail('BiDi %s: no answer in %d s' % (method, int(self.ws.s.gettimeout())))
            if m.get('id') != self.n: continue   # an event
            if m.get('type') == 'error':
                raise Fail('BiDi %s: %s: %s' % (method, m.get('error'), (m.get('message') or '').splitlines()[0][:200] if m.get('message') else ''))
            return m.get('result') or {}


def free_port():
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close()
    return p


def png_size(b):
    if b[:8] != b'\x89PNG\r\n\x1a\n': raise Fail('BiDi browsingContext.captureScreenshot: the data is not a PNG')
    return struct.unpack('>II', b[16:24])


def main():
    if len(sys.argv) != 3:
        sys.stderr.write('usage: phone-bidi.py <out-base> <url>\n'); return 2
    base, url = sys.argv[1], sys.argv[2]
    app = os.environ.get('PHONE_FIREFOX_APP') or '/Applications/Firefox.app'
    ff = os.path.join(app, 'Contents', 'MacOS', 'firefox')
    port_wait = float(os.environ.get('PHONE_PORT_WAIT') or 20)
    settle = float(os.environ.get('PHONE_SETTLE_MS') or 500) / 1000
    proc = prof = None
    tmps, outs = [], []

    def stop(*_):
        raise KeyboardInterrupt
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT): signal.signal(sig, stop)
    try:
        if not os.access(ff, os.X_OK): raise Fail('%s is not installed' % app)
        prof = tempfile.mkdtemp(prefix='phone-ff-')
        with open(os.path.join(prof, 'user.js'), 'w') as f:
            f.write(''.join('user_pref("%s", %s);\n' % kv for kv in (
                ('browser.shell.checkDefaultBrowser', 'false'), ('app.update.auto', 'false'), ('app.update.enabled', 'false'),
                ('datareporting.policy.dataSubmissionEnabled', 'false'), ('toolkit.telemetry.reportingpolicy.firstRun', 'false'),
                ('browser.aboutwelcome.enabled', 'false'), ('remote.active-protocols', '1'),
                ('ui.useOverlayScrollbars', os.environ.get('PHONE_OVERLAY_SCROLLBARS') or '1'))))
        port = free_port()
        proc = subprocess.Popen([ff, '--headless', '--remote-debugging-port=%d' % port, '-new-instance', '-profile', prof],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        ws = None; t0 = time.time(); last = 'nothing listens'
        while time.time() - t0 < port_wait:
            if proc.poll() is not None: raise Fail('Firefox exited with code %d before its port %d answered' % (proc.returncode, port))
            try:
                ws = WS(port, '/session', 60); break
            except Fail as e:
                last = str(e); time.sleep(0.2)
            except OSError as e:
                last = e.strerror or str(e); time.sleep(0.2)
        if ws is None: raise Fail('port %d did not answer in %g s (%s)' % (port, port_wait, last))
        b = Bidi(ws)
        b.cmd('session.new', capabilities={})
        ctx = b.cmd('browsingContext.create', type='tab')['context']   # the first context of getTree refuses setViewport
        b.cmd('browsingContext.setViewport', context=ctx, viewport={'width': W, 'height': SCREEN}, devicePixelRatio=SCALE)
        b.cmd('browsingContext.navigate', context=ctx, url=url, wait='complete')
        # a Mac set to "always show scroll bars" (a mouse, a CI runner) gives the page 375 css px beside a 15 px bar: take the bar away
        b.cmd('script.evaluate', target={'context': ctx}, awaitPromise=False, expression=
              'if (document.documentElement.clientWidth < %d) { var s = document.createElement("style"); '
              's.textContent = "html{scrollbar-width:none!important}"; document.documentElement.appendChild(s); } 0' % W)
        time.sleep(settle)
        r = b.cmd('script.evaluate', target={'context': ctx}, awaitPromise=False,
                  expression='Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, 1)')
        if r.get('type') == 'exception' or 'value' not in (r.get('result') or {}): raise Fail('BiDi script.evaluate: the page gave no height')
        height = int(r['result']['value'])
        if height <= SCREEN:   # short content: no blank tail (scrollHeight is never under the viewport's; the boxes are)
            r = b.cmd('script.evaluate', target={'context': ctx}, awaitPromise=False,
                      expression='Math.ceil(Math.max(document.documentElement.getBoundingClientRect().bottom, document.body ? document.body.getBoundingClientRect().bottom : 0, 1))')
            try: height = min(SCREEN, int(r['result']['value']))
            except (KeyError, TypeError, ValueError): pass
            vh = max(120, height)
            b.cmd('browsingContext.setViewport', context=ctx, viewport={'width': W, 'height': vh}, devicePixelRatio=SCALE)
            boxes = [('%s.png' % base, 0, vh)]
        else:
            boxes = [('%s-p%d.png' % (base, i + 1), y, min(SCREEN, height - y)) for i, y in enumerate(range(0, height, SCREEN))]
        for out, y, h in boxes:   # one screen per capture: no picture is ever taller than 1688 px, however long the page
            r = b.cmd('browsingContext.captureScreenshot', context=ctx, origin='document',
                      clip={'type': 'box', 'x': 0, 'y': y, 'width': W, 'height': h})
            data = base64.b64decode(r.get('data') or '')
            pw, ph = png_size(data)
            if pw != W * SCALE: raise Fail('Firefox drew the page %d px wide, not %d' % (pw, W * SCALE))
            tmp = '%s.tmp-%d' % (out, os.getpid()); tmps.append(tmp)
            with open(tmp, 'wb') as f: f.write(data)
            outs.append((tmp, out, pw, ph))
        for tmp, out, pw, ph in outs: os.replace(tmp, out)
        for tmp, out, pw, ph in outs: print('png %s %dx%d' % (out, pw, ph))
        return 0
    except Fail as e:
        print('phone-shot.sh: no picture: %s' % e); return 1
    except KeyboardInterrupt:
        print('phone-shot.sh: no picture: stopped'); return 1
    except OSError as e:
        print('phone-shot.sh: no picture: %s' % (e.strerror or e)); return 1
    finally:
        for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT): signal.signal(sig, signal.SIG_IGN)
        for t in tmps:
            try: os.remove(t)
            except OSError: pass
        if proc is not None and proc.poll() is None:   # its own pid (and the children in its process group), nobody else's
            for sig, wait in ((signal.SIGTERM, 3), (signal.SIGKILL, 3)):
                try: os.killpg(proc.pid, sig)
                except OSError: break
                try: proc.wait(wait); break
                except subprocess.TimeoutExpired: pass
        if prof: shutil.rmtree(prof, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
