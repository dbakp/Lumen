# Backup and restore

Settings → Privacy & data → Backup & restore. Create a backup, then use **Save or share backup** to save it in Files. The temporary share file is replaced by the next backup; a copy you saved in Files remains yours. Readable data export remains available separately and is not a backup format.

## Contents and limits

Version 1 includes profile, health goals, sleep settings/history/habits, meals and meal-photo thumbnails, water, workouts, conversations, symptoms, check-ins, plans/documents, imported daily metrics, import receipts and personal notes. Source IDs and plan dates/states are retained. A conversation counts as one record in the preview; its messages are included. The app retains extracted record text, rather than the original imported PDF.

API keys, OAuth credentials, HealthKit permissions, device-lock settings, subscription status, notification permissions and cached current-day Health readings are not restored. Connections and reminders remain as configured on the current device. Restoring logs never writes them back to Apple Health.

The archive is JSON with a version, creation date, encoded payload and SHA-256 checksum. The checksum detects accidental corruption; it does not establish the identity of whoever created a file. Backup files are not encrypted by Lumen and contain readable health data. Use a private storage location. Files over 100 MB, photos over 5 MB each or JPEG dimensions over 4096 pixels, unsafe photo names, duplicate IDs, malformed data and unsupported versions are rejected. Large libraries may require a future archive format. Original data is retained on any validation failure. Missing/unreadable local meal photos must be removed from the affected meal before backup.

## Restore rules

Choose a backup and inspect its date, categories and existing-record count. Confirm **Restore missing records** to merge. Current records with matching IDs win, even if the backup is newer. For imported days, current metric values win and missing metric keys can be added. Missing records are added. Photos belonging to added meals receive new names, preserving existing photos. Restoring a backup twice does not create duplicates. The conflict count is by record ID, not a count of changed fields.

Profile & preferences is off by default. Enabling it replaces name, body/activity goals, sleep settings, habits and personal notes. It keeps the current device lock, subscription state and onboarding completion; restored habit checkmarks reset. Restored documents and personal context have assistant sharing disabled. Existing local sharing choices remain intact unless personal context is replaced.

Only records already downloaded into Lumen are included. Reconnect external sources independently on a new device. A restore preview is a snapshot; the merge uses current device data at confirmation so later edits are preserved.

## Storage recovery

The app validates and encodes known domains before changing storage. It copies the existing data directory to a staging directory, applies records and photos there, then moves the existing directory aside and installs the complete staged directory. It retains the previous directory until installation succeeds. If interrupted before installation, next access recovers the previous directory. If installation finished, the installed copy is authoritative and the previous directory is removed. Unknown local domains are preserved by the initial copy. Credentials remain in Keychain throughout.

Standalone tests cover archive round-trip, photo bytes, conflicts, idempotency, consent, invalid files, future versions, payload corruption, path traversal, numeric overflow, failed staging and recovery after an interrupted directory move. The native scenario covers create → preview → restore → relaunch without duplicating plans. Actual Files/iCloud transfer and restoring on a second signed device still need physical-device validation.

Imported workout metadata (source, original end, filename, reported/elapsed duration and field warnings) is retained in optional version-1 fields. Restores reconcile matching external sessions while keeping the current local copy. Manual entries remain separate; ambiguous external sessions are preserved rather than merged on a broad time window. Older workout records without these fields continue to decode.


Confirmed local water/workout corrections retain stable IDs, original confirmation provenance and an optional `lastEditedAt` timestamp in version 1. Older records without this field still decode. Current records with the same ID continue to win during restore; deleting a record does not prevent an older backup from adding it again. Per-metric current-reading source/query metadata belongs to the current-day cache, which remains excluded from backups.
