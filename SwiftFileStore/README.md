# SwiftFileStore

An independent attachment store for iOS 16+ and macOS 13+. Apps always read their own local files. The library publishes explicit saves to an iCloud Drive container and automatically installs downloaded files into the local directory. It does not depend on SwiftStore, SQLite, CloudKit, or any business schema.

Available starting with SwiftStore 4.1.0. Add this repository as a Swift package dependency and select its `SwiftFileStore` product, or use a local dependency on the standalone package at `SwiftFileStore/`. The standalone package has no external dependencies.

## Basic usage

```swift
import SwiftFileStore

let files = try await SwiftFileStore(
    rootPath: "Reed",                        // default: ""
    iCloudEnabled: true,                     // default: true
    containerIdentifier: "iCloud.com.example.app" // default: nil
)

let file = try await files.importFile(
    from: sourceURL,
    path: "books/\(UUID().uuidString).pdf"
)
// Save this Codable FileReference with your business data.

let localURL = try await files.url(for: file)
let bytes = try await files.read(file) // intended for small files
let listing = try await files.list(in: "books")
```

`path` is a complete relative filename, including optional subdirectories. Omitting it generates a UUID filename with the source extension. The logical location is `default files directory / rootPath / path`. The local storage base defaults to Application Support; `localDirectory:` can override it. Do not modify registered files directly. New files written into the directory must be explicitly registered after writing finishes. Use one consistent container identifier spelling and storage base for a namespace.

Files are immutable attachments: a path cannot be overwritten with different bytes or reused after deletion. Save replacements at new paths and update business references yourself. Local imports retain the source file. The library never stores a business association or performs a database transaction.

`url(for:)` always returns an App-local file, never an iCloud URL. It automatically waits for missing content to download and be installed, with a default 30-second timeout. No extra snapshot is made when the local file is already present. Persist `FileReference`, not the absolute URL: app container paths can change after restore/reinstallation.

Use `reference(path:)` to construct a reference in the current scope when receiving a relative path through your business data. References from another scope are rejected.

## Register a file already in the local directory

`importFile(from:path:)` copies an external file into the store. `registerFile(path:)` adopts a completed file already inside `localRootURL` without copying or moving its content:

```swift
let path = "books/existing.pdf"
// If producing the file directly, write it under files.localRootURL first.
// Finish writing and close all writers before registration.
let file = try await files.registerFile(path: path)
let localURL = try await files.url(for: file)
```

`localRootURL` includes the configured `rootPath`; do not append `rootPath` again. The caller creates any parent directories needed when writing there. Registration validates the relative path and regular file, rejects symbolic links, and atomically records a local save and its upload intent (or local-only state when sync is disabled). It works offline. It reads the file to calculate a content digest but does not create another copy. Once registered, treat the file as immutable and use the store's APIs for access and deletion.

Repeated registration of unchanged managed content returns the same reference and preserves its origin and sync state, including for downloaded files. Changed content, conflicted/deleted paths, and case/Unicode aliases of managed paths are rejected. A missing file is not downloaded by this API. Use `reference(path:)` when you only need a reference, without registering a local save.

If the app exits before registration commits, the file remains unregistered; explicitly retry registration after restart. The library does not scan unregistered files for upload.

## Register files in an existing directory

```swift
let books = try await files.registerDirectory(path: "books") // recursive by default
let topLevel = try await files.registerDirectory(path: "books", recursive: false)
let all = try await files.registerDirectory() // everything under localRootURL
```

Returns individual `FileReference` values sorted by relative path, including unchanged files already registered. This scans once; later files need another explicit registration. Files are registered in place, with the same write-completion and immutability requirements as `registerFile`. Existing registrations retain their origin and sync state.

The batch validates every selected file before atomically committing its registration records. Validation, enumeration, or commit failure leaves no partial new registrations. Original files remain in place. Hidden files/directories (such as `.DS_Store`) are skipped; symbolic links, unsupported file types, conflicting content, and invalid paths cause failure. An empty directory returns an empty array and is not independently synchronized. `recursive: false` selects only immediate files.

## Protect a file while a reader or player uses it

```swift
let access = try await files.open(file)
// Pass access.url to the reader/player and retain access alongside it.
// After that consumer has completely stopped accessing the file:
await access.close()
```

An active `FileAccess` prevents the library from replacing or physically removing the file. Multiple readers get independent handles. A deletion hides the file from new readers immediately; physical cleanup waits for the last handle to close. `close()` is idempotent; deinitialization also schedules release, but explicit close is recommended. A bare URL does not register a reader.

`exportCopy(of:)` returns an independent temporary snapshot owned by the caller. Delete that export when finished. Use `exportRetainedCopy(of:)` to recover local content that is conflicted or awaiting physical deletion.

## Local-only mode and account changes

```swift
let local = try await SwiftFileStore(iCloudEnabled: false)
```

Local-only mode does not start an iCloud query, download, publication, or cloud deletion. Saves and local readers work without an account. Enabling sync later means closing the old instance and reopening the same scope with `iCloudEnabled: true`. Only explicitly saved files become uploads; downloaded copies do not.

An enabled store binds to the first available iCloud Drive identity before publishing. After that, new offline files and pending deletions remain bound to that account. Signing out preserves local files. Signing into another account blocks cloud work; it never uploads the old account's files to the new account. Use a separate scope and matching business context for a different account. Restoring the original account permits work to resume.

Turning this library's switch off does not stop transfers that the OS already owns or remove anything from iCloud. Downloaded local files remain readable.

## Deletion, errors, and status

```swift
let result = try await files.remove(file)
// result.isRegistered: durable deletion intent, hidden from new reads
// result.localCleanupPending: reader active or local deletion failed
// result.cloudDeletionPending: still needs an operation against the original container

let status = try await files.status(of: file)
for await event in await files.events() {
    // Refresh UI as needed. Progress is nil when the system has not provided it.
}
```

Saving succeeds when local content and recovery information have committed. Cloud quota errors never retroactively turn a successful local save into a failure. Pending uploads, downloads, deletes, account errors, and original system error details are exposed separately. Local disk or permission errors are thrown by the local operation; `FileIssue` categorizes system errors for display.

Cloud errors are recorded in status/events. `retryPendingOperations()` returns after a reconciliation pass; it does not throw each per-file cloud error or claim all transfers finished. Call it when the app returns to the foreground and for a Retry button. Metadata notifications and bounded retries also schedule work automatically. `waitUntilUploaded(_:timeout:)` observes upload acknowledgement; it does not force iCloud to transfer now. Caller cancellation/timeout does not destroy saved content or cancel another reader's download.

Do not infer a remote deletion from an empty/unavailable initial query. Live metadata removal events hide downloaded local files, respecting readers. If absence is ambiguous after a restart, local content is retained and never republished merely to fill the apparent gap. Uncertain interrupted publication is reconciled against cloud content; a missing target does not trigger a blind upload. The library keeps small local deletion records; it does not implement a cross-device tombstone protocol or guarantee delete-wins for concurrent writes.

Conflicting bytes at the same path are preserved, not automatically merged or overwritten. `conflicts(of:)` lists retained local/current-cloud/system-conflict versions; `exportVersion(_:of:)` exports a selected version. Review the exports, import desired bytes under new paths, update business references, and explicitly remove the old file. Nonlocal conflict versions may be unavailable until the system provides their content. Version IDs are session-scoped.

`evictCloudCache(for:)` can release the system's uploaded container cache while retaining the stable App-local file. It never clears unuploaded content or an unresolved conflict, and the system may download the container copy again.

## Storage and lifecycle

The App-local copy and the iCloud container copy may both occupy disk space. Temporary copies and conflicting versions can require additional space. This tradeoff is intentional: stable local access survives iCloud account unavailability. The library does not automatically evict App-local content.

The container's `Attachments/rootPath` directory is private app data outside `Documents`; discovery uses `NSMetadataQueryUbiquitousDataScope`. Enable iCloud Documents and the intended ubiquity container in the host app's entitlements. A CloudKit entitlement alone is insufficient. No CloudKit schema, push subscription, or database setup is required.

Hold the store for the application's lifetime. Call `close()` when replacing it; it refuses while readers are active and waits for current cloud work before releasing the directory lock. Concurrent or overlapping root paths under the same configured storage base/container are rejected. The standalone package supports iOS/macOS; other platforms importing the repository product can use local storage but have no native iCloud adapter here.

Actual network transfers are managed by the OS. Installing downloads into the App-local directory requires execution time in your app; automatic installation cannot be promised while the app is suspended or terminated.

## Validation

Run `swift test` in this directory. Tests use actual local filesystem persistence plus an internal deterministic cloud adapter. They cover offline saves, quota errors, stable URLs, multiple readers, deletion/account-change races during downloads, cancellation, recovery, conflicts, scope isolation, and preventing cached files from being uploaded again.

These tests do not replace two signed devices, a configured iCloud container, or a real full-quota account. Real iCloud propagation, quota recovery, background behavior, and account switching still require host-app/device validation.
