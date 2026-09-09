# Two-device test results — 2026-09-09

Historical run at revision `b121d7e` (`Complete sync transports and support iOS 16`).
These results do not certify the current checkout; see [run instructions](README.md) to repeat them.

| Client | Runtime | SQLite | Native `unixepoch('subsec')` |
| --- | --- | --- | --- |
| A | iOS 16.4, build 20E247 | 3.39.5 | NULL; shared SQL fallback used |
| B | iOS 18.2, build 22C150 | 3.43.2 | REAL; native implementation used |

Both simulator clients used actual SQLite databases and URLSession requests to
a loopback HTTP fixture, with separate persistent queues and journals.

| Scenario | Result |
| --- | --- |
| Bidirectional CRUD and no upload echo | PASS |
| Offline newest-wins in both upload orders | PASS |
| Equal timestamps and same-key batch arbitration | PASS |
| Delete versus stale edit, followed by recreation | PASS |
| Committed upload with lost response | PASS |
| Failed second upload batch, restart and resume | PASS |
| Failed second download page, restart and resume | PASS |
| Local edit during download | PASS |
| Local edit during upload | PASS |
| Failed download inbox followed by a local edit | PASS |
| Same key across multiple download pages | PASS |
| Transaction rollback | PASS |
| Mandatory time bounds at ±5000 / ±5001 ms | PASS |
| Journal identity and server database replacement | PASS |
| 24 randomly interleaved offline edits | PASS |
| SIGKILL after server commit, restart without duplicate upload | PASS |

CloudKit adapter: two test functions (three parameterized cases) passed on
macOS using two independent file journals and a shared conditional-save fixture.
These cover both conflict orders, deletion, recreation, lost-response restart and
equal-time first-commit retention. Actual Apple CloudKit was **not** contacted;
no signed host app/container configuration was supplied.

These runs do not validate cross-file crash atomicity
during a local SQLite commit or iOS background execution. The SIGKILL recovery
case concerns an already-persisted local change awaiting a server response.
