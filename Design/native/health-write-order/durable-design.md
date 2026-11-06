# Durable Health work · Batch43 candidate

This implements the full water, meal-component and weight contract declared in
`next-durable-audit.json`. It is a candidate under verification, not an accepted
application delivery. All eight original adversarial groups and the separate
signed-iPhone gate remain required.

## Local commit and ownership

`HealthWriteJournal` contains a device-local owner, lifecycle, immutable event
payload, per-component identities, desired save/delete generation and checked
receipts. Quick water and meals stage their local JSON and journal in the same
recoverable directory swap. Weight stages goals, today's snapshot and journal
together, retaining the captured storage-revision and live-sync guards. The
worker starts only after this commit. A failed stage or installation must leave
the prior local and intent files available and send no external operation.

New saves are queued only when Lumen's Health connection has been requested at
the time of the local mutation. Connecting later does not manufacture writes
from unconnected local history. A requested deletion remains pending even if
Health is currently paused. Missing old intent is a legacy installation;
unreadable, non-regular, ambiguous JSON or invalid intent is a surfaced error,
never an empty replacement queue.

The journal is not part of `BackupSnapshot`, the encrypted package record kinds,
or readable exports. Restore explicitly preserves this installation's journal,
rotates its lifecycle inside the same directory transaction, withdraws older
unstarted saves and retains requested deletions. Restored records themselves
cannot enqueue external work.

Reset uses a checked replacement-directory commit before clearing live local
state/defaults. Only incomplete requested deletions survive, with opaque
source-owned identities and component types; measurement amounts/dates and
completed receipts are removed. Their generations change so a callback from
before reset cannot acknowledge the new pending operation. This does not turn
reset into a bulk Health erasure; its native confirmation explains the pending
removal exception. Credential removal still precedes local reset. The broader
late-Strava callback/privacy-erasure audit remains separate and open.

## Replay and acknowledgement

Each sample's HealthKit sync identifier includes a namespace, journal owner,
event UUID and component type. Its immutable payload always uses version1.
Meal calories, protein, carbs, fat and fiber have separate identifiers; each
weight log has an independent persisted event identity. Apple documents that
sync identifiers prevent duplicate samples and describes ignoring the same
version arriving on another device in [Synchronize health data with HealthKit,
WWDC2020, transcript around lines256–283](https://developer.apple.com/videos/play/wwdc2020/10184/).
This resolves the equal-version documentation gap in the earlier symbol-only
investigation; actual adapter and signed-device behavior still need verification.

The adapter checks write authorization for the particular type, sends a save
with original timestamp/quantity and stable metadata, then queries its own
source plus exact owner/event/sync identifier. A receipt requires one matching
sample with the original value, date and version. For deletion, query only this
source and exact identity, delete those returned samples, then check absence.
Legacy deletion uses the old Lumen water/meal ID plus the same explicit source
filter; legacy records can never manufacture a save. Denied read access still
allows reading samples the app saved itself, as documented in Apple's
[Health authorization guide](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Recovery has one task per event and at most four active events. One failed meal
type does not prevent water/weight work. Every callback reloads current intent;
a superseded save cannot acknowledge its later deletion. A receipt commit must
compare the current journal with the exact pre-receipt state under the storage
write lock. Failure leaves the original operation pending for idempotent replay.
Failures stop that event for the current pass; retry or a later foreground pass
can try again. No timer or callback timeout fabricates completion.

## Current evidence and limits

`durable-baseline-r1.swift` uses the unchanged production in-process queue in two
actual processes. Its local records remain while queued external operations
are lost. It does not invoke HealthKit or claim HealthStore integration.

Focused tests exercise the production journal, recovery worker and Foundation
linked transactions with a controlled adapter. Two new-process pairs cover
commit-before-worker and success-before-receipt. The controlled adapter models
the documented sync identity contract; it does not prove HealthKit applies it.
Current source archives and complete producer logs retain failed compiler/test
trials and the exact tested boundary. Native integration, actual simulator
HealthKit, normal/dark/largest recovery UI, continuing design critique, broader
regressions/Release, publication and the signed-device gate remain open until
their own authoritative evidence exists.

Current R6 closes the implementation gap with a checked, nonsynchronizing AfterFirstUnlockThisDeviceOnly Keychain owner. Runtime reads and adapter entry reject a copied journal owner. Explicit device setup replaces only foreign intent and queues no imported history; same-device pending deletes retain their owner through credential erasure/reset. Fifty focused checks and two native18-check cases cover the modeled copy/setup/reset boundary and actual Keychain identity policy. Physical backup migration remains a separate unverified gate; the simulator does not prove an OS restore on another iPhone.

Actual HealthKit R2 now passes47 simulator checks at sourceR6. Seven types retain one logical sync-identified sample per type across replay, unchanged measured quantity/date/source and durable receipts. Six water/meal components are deleted through the production adapter; exact fixture cleanup is queried absent. All seven framework object UUIDs change on replay, so receipts/deletions correctly use sync metadata. The initial extra UUID-stability assertion remains failed with exact source/log/report. This observational result does not claim an Apple-confirmed bug or signed-device behavior. Native process termination, foreign-source/permission cases, complete lifecycle/archive/UI/critic and physical-device gates still need their own evidence.

R8 adds three verified actual native/HealthKit process pairs (six XCTest cases,102 checks). Known boundaries are post-local-commit/pre-dispatch, successful external operations before failed receipts, and save/Undo before receipt followed by termination. Every preparation is read back by the host before resume; both phases use the same source/binary and different actual PIDs, with five exact files, original payloads, actual samples and durable receipts checked. DEBUG fixture dispatch/observer isolation does not substitute for an in-flight daemon/power-loss or unmodified normal-startup test. Exact synthetic samples are removed and queried absent after each completed pair. All original remaining groups stay open.
