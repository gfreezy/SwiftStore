"""In-memory, loopback-only HTTP fixture. Not a production sync server.

Conflict decisions inspect only key and updatedAt; payload remains opaque.
Fault controls are Python methods, never exposed as unauthenticated HTTP routes.
"""
import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class SyncServer(ThreadingHTTPServer):
    def __init__(self):
        super().__init__(('127.0.0.1', 0), Handler)
        self.lock = threading.RLock()
        self.identity = 'two-device-test-server'
        self.spaces = {}
        self.requests = []
        self.fault = None
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return 'http://127.0.0.1:' + str(self.server_port)

    def inject(self, path, kind, skip=0, marker=None):
        with self.lock:
            self.fault = dict(path=path, kind=kind, skip=skip, marker=marker)

    def take_fault(self, path):
        with self.lock:
            if not self.fault or self.fault['path'] != path:
                return None
            if self.fault['skip']:
                self.fault['skip'] -= 1
                return None
            result, self.fault = self.fault, None
            return result

    def count(self, namespace):
        with self.lock:
            return len(self.spaces.get(namespace, {}).get('history', []))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.handle_sync()

    def do_POST(self):
        self.handle_sync()

    def respond(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('X-SwiftStore-Server-ID', self.server.identity)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the worker is killed during a held response.

    def handle_sync(self):
        url = urlparse(self.path)
        path = url.path.rsplit('/', 1)[-1]
        query = parse_qs(url.query)
        namespace = query.get('namespace', [''])[0]
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or '{}')
        with self.server.lock:
            self.server.requests.append((namespace, path, body))
        if self.headers.get('Authorization') != 'Bearer integration-test':
            return self.respond(401, {})
        identity = self.headers.get('X-SwiftStore-Server-ID')
        if identity and identity != self.server.identity:
            return self.respond(409, {})
        fault = self.server.take_fault(path)
        if fault and fault['kind'] == 'fail':
            return self.respond(503, {})
        with self.server.lock:
            state = self.server.spaces.setdefault(namespace, dict(current={}, history=[]))
            current, history = state['current'], state['history']
            if path == 'push':
                rejected = set()
                for record in body['changes']:
                    key = record['key']
                    old = current.get(key)
                    if old is None or record['updatedAt'] > old['updatedAt']:
                        committed = dict(record, sequence=len(history) + 1)
                        current[key] = committed
                        history.append(committed)
                    else:
                        rejected.add(key)
                result = {'rejected': [dict(key=k, sequence=current[k]['sequence']) for k in sorted(rejected)]}
            elif path == 'pull':
                cursor = int(query.get('cursor', ['0'])[0])
                limit = int(query['limit'][0])
                records = [r for r in history if r['sequence'] > cursor][:limit]
                next_cursor = records[-1]['sequence'] if records else cursor
                result = dict(changes=records, cursor=next_cursor, hasMore=next_cursor < len(history))
            elif path == 'records':
                result = {'records': [current[k] for k in body['keys']]}
            else:
                return self.respond(404, {})
        if fault:
            if fault['kind'] == 'drop':
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            if fault['kind'] == 'hold':
                marker = Path(fault['marker'])
                marker.touch()
                deadline = time.monotonic() + 15
                while not Path(str(marker) + '.release').exists():
                    if time.monotonic() > deadline:
                        return self.respond(504, {})
                    time.sleep(0.01)
        self.respond(200, result)
