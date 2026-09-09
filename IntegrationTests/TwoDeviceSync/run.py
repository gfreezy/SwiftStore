"""Run isolated, persistent clients on two booted simulators against real HTTP."""
import argparse
import json
import random
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from server import SyncServer

parser = argparse.ArgumentParser()
parser.add_argument('--worker', required=True, type=Path)
parser.add_argument('--device-a', required=True)
parser.add_argument('--device-b', required=True)
parser.add_argument('--output', type=Path)
parser.add_argument('--only', help='Comma-separated scenario names')
args = parser.parse_args()
root = Path(tempfile.mkdtemp(prefix='swiftstore-two-device-'))
server = SyncServer()
results = []
invocations = []


class Pair:
    def __init__(self, name):
        self.name = name
        self.ids = [str(uuid.uuid4()), str(uuid.uuid4())]

    def call(self, side, expect_error=False, expect_killed=False, **kwargs):
        directory = root / self.name / str(side)
        command = dict(directory=str(directory), server=server.url, namespace=self.name,
                       deviceID=self.ids[side], edits=[], sync=False, rollback=False, offsetMs=0)
        command.update(kwargs)
        input_path = root / ('command-' + str(uuid.uuid4()) + '.json')
        input_path.write_text(json.dumps(command))
        proc = subprocess.run(['xcrun', 'simctl', 'spawn', [args.device_a, args.device_b][side],
                               str(args.worker.resolve()), str(input_path)], capture_output=True, text=True, timeout=45)
        if expect_killed:
            assert proc.returncode in (-9, 137), (proc.returncode, proc.stdout, proc.stderr)
            Path(command['requestMarker'] + '.release').touch()
            invocations.append(dict(command=command, result={'killed': True, 'exitCode': proc.returncode}))
            return {'killed': True}
        lines = [line[7:] for line in proc.stdout.splitlines() if line.startswith('RESULT ')]
        assert proc.returncode == 0 and lines, (command, proc.stdout, proc.stderr)
        result = json.loads(lines[-1])
        invocations.append(dict(command=command, result=result))
        assert ('error' in result) == expect_error, result
        return result

    def sync(self, side, **kwargs):
        return self.call(side, sync=True, **kwargs)

    def converge(self, expected):
        for side in (0, 1, 0, 1):
            self.sync(side)
        for side in (0, 1):
            result = self.call(side)
            actual = {r['id'].lower(): r['title'] for r in result['rows']}
            assert actual == expected, (self.name, side, actual, expected)


def edit(key, title, stamp=None):
    value = dict(id=key, title=title)
    if stamp is not None:
        value['timestamp'] = stamp
    return value


def scenario(name, function):
    start = time.monotonic()
    function(Pair(name))
    result = dict(scenario=name, seconds=round(time.monotonic() - start, 2), status='PASS')
    results.append(result)
    print(json.dumps(result), flush=True)


def crud(p):
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    first = p.call(0, edits=[edit(a, 'A')])
    second = p.call(1, edits=[edit(b, 'B')])
    print('RUNTIMES', first['os'], first['sqlite'], first['nativeSubsec'], '|', second['os'], second['sqlite'], second['nativeSubsec'], flush=True)
    p.sync(0)
    p.converge({a: 'A', b: 'B'})
    before = [p.call(s)['logCount'] for s in (0, 1)]
    changes = server.count(p.name)
    p.converge({a: 'A', b: 'B'})
    assert [p.call(s)['logCount'] for s in (0, 1)] == before
    assert server.count(p.name) == changes == 2
    p.call(1, edits=[edit(a, 'edited')])
    p.sync(1)
    p.converge({a: 'edited', b: 'B'})


def conflicts(p):
    keys = [str(uuid.uuid4()) for _ in range(2)]
    stamp = time.time() - 10
    for i, key in enumerate(keys):
        p.call(0, edits=[edit(key, 'older', stamp)])
        p.call(1, edits=[edit(key, 'newer', stamp + 1)])
        p.sync(i)
        p.sync(1 - i)
    p.converge(dict.fromkeys(keys, 'newer'))


def ties(p):
    key = str(uuid.uuid4())
    stamp = time.time() - 10
    p.call(0, edits=[edit(key, 'first', stamp)])
    p.call(1, edits=[edit(key, 'second', stamp)])
    p.sync(0)
    p.converge({key: 'first'})
    # Same-key batch: descending timestamps must restore the server's winner.
    p.call(1, edits=[edit(key, 'batch-newer', stamp + 3), edit(key, 'batch-stale', stamp + 2)])
    p.sync(1)
    p.converge({key: 'batch-newer'})


def deletion(p):
    key = str(uuid.uuid4())
    old = time.time() - 20
    p.call(0, edits=[edit(key, 'initial', old)])
    p.sync(0)
    p.sync(1)
    p.call(1, edits=[edit(key, 'stale edit', old + 1)])
    p.call(0, edits=[edit(key, None)])
    p.sync(0)
    p.converge({})
    p.call(1, edits=[edit(key, 'recreated')])
    p.sync(1)
    p.converge({key: 'recreated'})


def lost_response(p):
    key = str(uuid.uuid4())
    p.call(0, edits=[edit(key, 'once')])
    server.inject('push', 'drop')
    p.sync(0, expect_error=True)
    assert server.count(p.name) == 1
    p.converge({key: 'once'})
    assert server.count(p.name) == 1


def batch_failure(p):
    values = {str(uuid.uuid4()): str(i) for i in range(7)}
    p.call(0, edits=[edit(k, v) for k, v in values.items()])
    server.inject('push', 'fail', skip=1)
    p.sync(0, expect_error=True)
    assert server.count(p.name) == 2
    p.converge(values)
    assert server.count(p.name) == 7


def page_failure(p):
    values = {str(uuid.uuid4()): str(i) for i in range(7)}
    p.call(0, edits=[edit(k, v) for k, v in values.items()])
    p.sync(0)
    server.inject('pull', 'fail', skip=1)
    p.sync(1, expect_error=True)
    state = json.loads((root / p.name / '1/transport.json').read_text())
    assert state['cursor'] == 2
    p.converge(values)
    assert p.call(1)['logCount'] == 0


def concurrent(p):
    key = str(uuid.uuid4())
    stamp = time.time() - 10
    p.call(0, edits=[edit(key, 'base', stamp)])
    p.sync(0)
    p.sync(1)
    p.call(1, edits=[edit(key, 'remote', stamp + 1)])
    p.sync(1)
    marker = str(root / (p.name + '-request'))
    server.inject('pull', 'hold', marker=marker)
    result = p.sync(0, duringSync=edit(key, 'local during download', stamp + 2), requestMarker=marker)
    assert result['rows'][0]['title'] == 'local during download', result
    p.converge({key: 'local during download'})


def concurrent_upload(p):
    key = str(uuid.uuid4())
    stamp = time.time() - 10
    p.call(0, edits=[edit(key, 'uploading', stamp)])
    marker = str(root / (p.name + '-request'))
    server.inject('push', 'hold', marker=marker)
    result = p.sync(0, duringSync=edit(key, 'next edit', stamp + 1), requestMarker=marker)
    assert result['rows'][0]['title'] == 'next edit', result
    assert result['logCount'] == 2
    p.converge({key: 'next edit'})


def old_inbox_then_edit(p):
    key = str(uuid.uuid4())
    stamp = time.time() - 10
    values = {key: 'server winner', **{str(uuid.uuid4()): str(i) for i in range(3)}}
    p.call(0, edits=[edit(k, v, stamp + 1) for k, v in values.items()])
    p.sync(0)
    server.inject('pull', 'fail', skip=1)
    p.sync(1, expect_error=True)
    p.call(1, edits=[edit(key, 'stale after failed pull', stamp)])
    p.sync(1)
    p.converge(values)


def many_same_key_pages(p):
    key = str(uuid.uuid4())
    stamp = time.time() - 10
    p.call(0, edits=[edit(key, str(i), stamp + i / 10) for i in range(9)])
    p.sync(0)
    p.converge({key: '8'})
    assert p.call(1)['logCount'] == 0
    assert server.count(p.name) == 9


def shuffled_edits(p):
    randomizer = random.Random(20260909)
    keys = [str(uuid.uuid4()) for _ in range(5)]
    stamp = time.time() - 20
    winners = {}
    for step in range(24):
        side = randomizer.randrange(2)
        key = randomizer.choice(keys)
        title = f'edit-{step}'
        winners[key] = title
        p.call(side, edits=[edit(key, title, stamp + step / 8)])
        if randomizer.random() < 0.4:
            p.sync(randomizer.randrange(2))
    p.converge(winners)


def killed_after_commit(p):
    key = str(uuid.uuid4())
    p.call(0, edits=[edit(key, 'survives SIGKILL')])
    marker = str(root / (p.name + '-request'))
    server.inject('push', 'hold', marker=marker)
    p.sync(0, killDuringSync=True, requestMarker=marker, expect_killed=True)
    assert server.count(p.name) == 1
    p.converge({key: 'survives SIGKILL'})
    assert server.count(p.name) == 1


def rollback(p):
    key = str(uuid.uuid4())
    result = p.call(0, edits=[edit(key, 'rolled back')], rollback=True)
    assert result['logCount'] == 0 and not result['rows']
    p.converge({})
    assert server.count(p.name) == 0


def time_gate(p):
    key = str(uuid.uuid4())
    p.call(0, edits=[edit(key, 'pending')])
    for offset in (-5001, 5001):
        before = len(server.requests)
        error = p.sync(0, offsetMs=offset, expect_error=True)['error']
        assert 'timeOutOfSync' in error and len(server.requests) == before
    p.sync(0, offsetMs=-5000)
    p.sync(1, offsetMs=5000)
    p.converge({key: 'pending'})


def identities(p):
    key = str(uuid.uuid4())
    p.call(0, edits=[edit(key, 'initial')])
    p.sync(0)
    assert 'stateIdentityMismatch' in p.sync(0, namespace='other', expect_error=True)['error']
    assert 'stateIdentityMismatch' in p.sync(0, deviceID=str(uuid.uuid4()), expect_error=True)['error']
    old_identity = server.identity
    server.identity = 'replacement-server'
    try:
        p.call(0, edits=[edit(key, 'pending')])
        p.sync(0, expect_error=True)
        assert server.count(p.name) == 1
    finally:
        server.identity = old_identity
    p.converge({key: 'pending'})


try:
    for name, function in [('crud-no-echo', crud), ('offline-newest-both-orders', conflicts),
                           ('ties-and-same-key-batch', ties), ('delete-stale-recreate', deletion),
                           ('commit-response-lost', lost_response), ('upload-batch-restart', batch_failure),
                           ('download-page-restart', page_failure), ('write-during-download', concurrent),
                           ('write-during-upload', concurrent_upload), ('failed-inbox-then-local-edit', old_inbox_then_edit),
                           ('same-key-many-pages', many_same_key_pages), ('transaction-rollback', rollback), ('mandatory-time-bounds', time_gate),
                           ('kill-after-server-commit', killed_after_commit), ('state-server-identity', identities), ('shuffled-offline-edits', shuffled_edits)]:
        if not args.only or name in args.only.split(','):
            scenario(name, function)
finally:
    server.shutdown()
    report = dict(directory=str(root), scenarios=results, invocations=invocations, requests=server.requests)
    output = args.output or root / 'report.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2))
    print('REPORT', output, flush=True)
