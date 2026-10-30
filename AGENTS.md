# Lumen working instructions

Follow `docs/CONTINUE_ON_NEW_COMPUTER.md` for the ongoing product goal and verified delivery workflow.

## Storage discipline — user preference

This computer has limited storage. Apply this policy on every run:

- Check available disk space before substantial builds, fixture generation or large downloads, and review storage again before finishing.
- Keep the working repository, current inputs, the supplied design skill and files needed for the next step. Preserve unrelated projects and user files.
- After verification, retain useful screenshots, compact test outcomes and source/provenance details in the repository. Confirm required changes/evidence reached GitHub before deleting their redundant local copies.
- Remove this task's obsolete temporary source mirrors, duplicate screenshots, raw test-result bundles, synthetic large fixtures and generated share files when no longer needed. Raw `/tmp` paths in verification reports are historical references, not permanent archives.
- Clear task-owned Xcode build output and Swift package build caches after a completed batch when they will not immediately be reused. During active work, reuse one appropriate build directory per platform instead of accumulating copies; never delete a cache while its build/test process is running.
- Generate large fixtures only for the checks that need them; delete them afterward. Remove only known synthetic fixtures from the dedicated test simulator, without erasing shared runtimes, other simulators or personal data.
- Do not indiscriminately clear system/browser/application caches. Scope deletion to verified task-owned, disposable data and do not follow symlinks into other locations.
- Report the space actually recovered. Do not launch a new build just to verify a documentation-only cleanup change.
