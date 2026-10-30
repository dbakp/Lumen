# Backup and restore

Settings → Privacy & data → Backup & restore. New backups are encrypted and use the `.lumenbackup` extension. Readable **Export my data** files use a separate, unencrypted format. Choose **Recover a readable export** for their own reviewed conversion; the backup file/password controls remain specific to typed backups. See [Readable exports](READABLE_EXPORT.md).

## Save and bring back a copy

Choose **Create backup**, enter and repeat a password of at least 12 characters, then choose **Create encrypted backup**. Lumen cannot recover the password. The app does not save it or include it in the archive. New passwords are limited to 256 UTF-8 bytes; passwords are compared byte for byte, including spaces.

When the file is ready, use **Save or share backup** to save it to Files. The share copy is temporary: leaving this screen removes it, and a successful replacement export replaces it. A failed or cancelled replacement keeps the previous share copy. A copy already saved in Files remains yours. Only encrypted output is retained for sharing; the export's temporary photo copies are removed after encryption.

Choose **Choose backup** to open an encrypted file or an older version-1 JSON backup. Encrypted files require their password before a preview appears. An incorrect password or damaged file cannot produce a restorable preview. Lumen copies the selected file privately before releasing Files access, so unlocking can be retried without losing that selection. **Dismiss file**, **Dismiss preview** or leaving the screen releases the associated temporary files.

Review the creation date, format, category counts and **Already on this iPhone** count. **Restore missing records** opens a confirmation with **Keep reviewing** and **Restore records**. Nothing is restored merely by selecting or unlocking a file. Progress reports actual processed items or bytes. **Cancel** stops file preparation, encryption, reading, photo validation or restore staging; it cannot interrupt the short final directory installation after it has committed. Leaving the screen also requests cancellation. Cancelling a pending Files-provider request calls the platform coordinator's cancellation API; actual iCloud/provider behavior still needs device validation.

## Contents and limits

Both versions include profile, health goals, sleep settings/history/habits, meals and meal-photo thumbnails, water, workouts, conversations, symptoms, check-ins, plans/documents, imported daily metrics, import receipts and personal notes. Source IDs, original confirmation/correction timestamps and plan dates/states are retained. A conversation counts as one record; its messages are included. The app retains extracted document text, rather than the original imported PDF.

API keys, OAuth credentials, HealthKit permissions, device-lock settings, subscription state, notification permissions and cached current-day Health readings are not restored. Connections and reminders remain configured on the current device. Restoring logs never writes them back to Apple Health. Only records already downloaded into Lumen are included; reconnect external sources independently.

| Format | File and expanded-data bounds | Record and photo bounds |
|---|---|---|
| Version 2, encrypted `.lumenbackup` | 2 GiB each for the encrypted file and expanded stream | 100 MiB of record metadata; 32 MiB per encoded record |
| Version 1, unencrypted JSON | 100 MiB file | Existing typed validation and photo bounds |
| Both | At most 500,000 history records; 200,000 per domain/habits | JPEG photos at most 5 MiB each, at most 4096 × 4096 pixels |

The interface uses the shorter labels “2 GB”, “100 MB” and “5 MB”. Version 2 streams individual records and raw photo files; it does not build a base64 copy of the whole archive in memory. Metadata remains bounded in memory, and each JPEG is decoded individually before a preview is accepted. Existing local photos must be present and readable to create a backup. Unsafe paths, duplicate identities, missing referenced photos, unsupported versions, malformed numeric data, missing/extra frames, modified/truncated encrypted files and exceeded limits are rejected before installation.

Large operations need free space for the selected archive, decrypted preview photos and a staged copy of current storage. Storage errors leave the current records in place.

## Encryption and compatibility

Version 2 uses Apple's `AppleArchive` encrypted byte stream with the password/scrypt profile `hkdf_sha256_aesctr_hmac__scrypt__none` and LZFSE compression. A framed manifest, typed records and raw photos are inside the authenticated container. Authentication includes the stream's declared size; the reader checks the complete stream, declared counts and end-of-file before returning a preview. There is no custom encryption primitive or new third-party cryptography dependency. The archive does not store your password. Record contents are encrypted; the shared filename still reveals the backup date, and file size remains visible. Possessing a valid file/password does not establish who authored its records.

Version 1 remains readable through its original typed JSON decoder and SHA-256 checksum. That checksum detects corruption, not authorship. Older JSON backups are explicitly labelled **Older, unencrypted backup**. Restoring one and creating a new backup produces the encrypted format, including the device's current merged records. General readable exports use the separate [reviewed recovery](READABLE_EXPORT.md) path, with no photo files and independent category/settings selection. They are never treated as authenticated encrypted backups.

The platform implementation is used directly. This is not a claim of an independent cryptographic audit, full 2 GiB device testing or release compliance approval. See [verification evidence](VERIFICATION.md) for the actual synthetic files and native scenarios exercised.

## Restore rules

Current records with matching IDs win, even when the backup is newer. Imported days keep current metric values and add only missing keys. Missing records are added. External workout reconciliation retains its existing source/session rules; ambiguous sessions stay separate and manual sessions are not merged broadly. Added meal photos receive new names, preserving existing photos. Restoring the same backup twice does not add duplicate records or photos. The conflict count is by record identity, not changed fields. Deleting a local record does not prevent an older backup from adding it again.

**Restore profile & preferences** is off by default. Enabling it replaces name, body/activity goals, sleep settings, habits and personal notes. It keeps device lock, subscription state and onboarding completion; restored habit checkmarks reset. Newly restored documents and replaced personal context have assistant sharing off. Existing local document sharing choices remain intact.

A preview is a snapshot. Confirmation captures current metadata again and merges against that copy. A local write during off-thread staging invalidates the pending installation: the user gets an error and their current records remain. A shared write barrier makes the revision check and directory installation indivisible with respect to local writes. Store reload and companion refresh occur after this barrier is released.

## Storage and recovery

File-provider copying, encryption, decoding, JPEG validation and restore staging run off the main actor. File-copy buffers are 64 KiB. Staging clones existing local storage, preserving unknown domains, then applies merged metadata and file-backed photos. Symlinks and unsafe relative paths are refused. The final commit moves the current directory aside, installs the prepared directory and retires the previous copy for background cleanup. An unsuccessful installation recovers the previous directory. After an interrupted move, the existing directory-recovery rules recover the previous copy when necessary.

Operation directories are private, with protected temporary data files. Preview/share ownership lasts until the worker and screen release it; large cleanup runs off the main actor. Abandoned backup workspaces and the old temporary JSON share folder are removed before the first new backup workspace in an app session. Abandoned restore/retired directories captured at initial local-store access are cleaned in the background; a newly running restore's directory is not included. Credentials remain in Keychain.

Production-logic checks and actual simulator runs are listed in [Verification](VERIFICATION.md). Actual iCloud transfer, restoring on a second signed physical device, worst-case memory/storage pressure, every interruption/background path, VoiceOver and release validation remain open.
