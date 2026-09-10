# Two-device synchronization integration tests

Runs the actual SwiftStore SQLite, pre-update tracking, SyncManager and
HTTPSyncTransport code in separate iOS Simulator processes. Each device has its
own on-disk business database, changelog, device ID and transport journal. The
clients use URLSession against a loopback HTTP fixture. Every command relaunches
the worker with the same files; one scenario additionally kills it with SIGKILL.

## Run

Requires Apple Silicon, Xcode, Python 3 and two installed, booted iOS simulators.
No signing or host app is needed for these command-line simulator workers.

```sh
xcrun simctl list devices available
xcrun simctl boot <device-a-uuid>
xcrun simctl boot <device-b-uuid>
python3 IntegrationTests/TwoDeviceSync/build.py /tmp/swiftstore-two-device/Worker
python3 IntegrationTests/TwoDeviceSync/run.py \
  --worker /tmp/swiftstore-two-device/Worker \
  --device-a <device-a-uuid> \
  --device-b <device-b-uuid> \
  --output /tmp/swiftstore-two-device/report.json
```

Use `--only name1,name2` to rerun selected scenarios. The JSON report contains
scenario results, every worker command/result, HTTP requests and the temporary
state directory. A failed assertion exits nonzero and still writes the report.
Existing user databases are never used. Temporary databases remain available
for diagnosis. The HTTP fixture binds only to loopback, uses a test-only token,
keeps payloads opaque, and resolves conflicts using only key and updatedAt.
It is an in-memory test fixture, not a production server implementation.

## Coverage

- Bidirectional CRUD; downloaded rows generate no local changelog or upload echo.
- Offline conflicts in both upload orders; equal times retain the first commit.
- Multiple edits to one key within a batch and across multiple download pages.
- Delete versus stale edit; later recreation.
- Server commits then loses its response; retries do not append duplicate changes.
- Second upload batch / second download page fails; persistent progress resumes.
- Unapplied download followed by a conflicting local edit.
- Local writes while upload or download is held in flight.
- Failed local transaction rolls back both business rows and captured changes.
- Startup time gate: ±5000 ms accepted, ±5001 ms rejected before any HTTP request.
- Endpoint/namespace/device journal identity and server database identity checks.
- SIGKILL after server commit and before its response, followed by recovery.
- Deterministic random interleaving of 24 edits across two offline clients.

NTP **network results are injected** into an isolated startup cache for each worker process;
the real cache and tolerance check still run. This tests the gate, not public NTP reachability.
Simulator workers do not test app suspension, signing, entitlements or APNs.

## CloudKit scope

`CloudKitTwoClientTests` additionally exercises two independent file journals
against a shared conditional-save fixture. The real iOS 16 operations adapter
handles newer/stale edits, tombstones, recreation, equal timestamps and a lost
commit response across restart. Revision receipts model SDK change tags at the
network boundary; this does not verify native CloudKit tag encoding.

```sh
swift test --filter CloudKitTwoClientTests
```

Actual Apple CloudKit / CKSyncEngine / background push testing requires a signed
host app with CloudKit entitlements, a configured container and two devices
signed into the same test iCloud account. It is not covered by the HTTP simulator
run or the conditional-save fixture. See [historical test results](RESULTS.md) for a version-specific run.
