# Third-party components

## ZIPFoundation

- Official repository: https://github.com/weichsel/ZIPFoundation
- Pinned version: 0.9.20
- Pinned revision: 22787ffb59de99e5dc1fbfe80b19c97a904ad48d
- License: MIT; notice shipped in Lumen/Resources/ZIPFoundation-LICENSE.txt and shown under Settings → Open-source licenses.
- Used by the iPhone app and the local logic-check executable. Watch and widget targets do not link it.
- Both Package.resolved files must retain the same revision when updating. Run the actual logic suite and native import flow after dependency updates.

ZIPFoundation performs inflation and CRC calculation. Lumen bounds directory offsets/sizes before handing a private snapshot to the library, limits actual extracted bytes, compares CRC and exact size, and never extracts paths supplied by the archive. The preflight normalizes validated zero-valued ZIP64 local offsets in its private copy because the 0.9.20 effective-offset getter otherwise falls back to the 32-bit placeholder. Compatibility and original-file immutability are covered by regression fixtures.

The format preflight follows metadata layouts in the PKWARE ZIP specification; it is not a second decompression implementation. It supports the bounded, single-disk stored/Deflate layouts used for this import flow. General-purpose encrypted, multipart or extensible ZIP64 archive support is not claimed.

The command-line checks use a temporary build directory to avoid Finder metadata affecting local Swift resource signing. The first run needs network access to resolve the pinned dependency. Subsequent builds use Swift Package Manager's cache.
