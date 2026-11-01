# Personal context and reminder saves

Batch38 has passed its scoped verification and design review; published as `a83918a1d7dcd5a4739e8f37e0a71d95fd7f70d3` with exact GitHub read-back before scoped cleanup. Current results, source boundaries and failed runs are recorded with [the evidence](../Design/native/consent-preferences/README.md). This page describes the implemented behavior, not release acceptance.

## Personal notes and sharing

The personal-context editor keeps a separate draft. Save writes the notes and sharing choice together through checked local storage before publishing the replacement or closing the editor. **Saved sharing: On/Off** reports the current saved choice; **Changes not saved** identifies a draft. A failed opt-in does not enable sharing. A failed withdrawal explicitly says saved notes and sharing have not changed, retains the draft and offers retry.

Cancel on a changed draft asks whether to discard it. **Keep draft** returns to the unsaved edits; **Discard** leaves the saved notes and sharing choice unchanged. A revision guard rejects a draft based on older saved notes, including after restore. In that stale-draft choice, **Keep draft** retains the draft; **Reload** explicitly replaces its unsaved edits with the current saved version. The explanation states that replacement before the choice. It does not silently merge or overwrite newer notes.

At accessibility text sizes the complete field labels appear above their native inputs. While a field is being edited, Done appears in the native navigation bar to finish editing before moving through the form. Done retains the draft and does not save notes or sharing. Save remains the consent boundary, and Cancel is available on a changed draft after editing finishes. The editor retains the existing notes and JSON format; no health measurement or Apple Health sample is created.

Sharing starts off. When saved on, personal notes accompany questions to the selected provider through the existing assistant-context builder. Saving off omits them from fresh context. It does not recall notes already attached to an ongoing question or erase earlier conversation/provider history. User-entered allergies, injuries and constraints are reference notes; Lumen does not verify them. Broader ongoing-request/history privacy review remains open.

## Reminder preferences and permission

Connections, Settings and onboarding share one checked enable service. A successful system permission reply must still belong to the latest active requesting screen before enabled preferences can be saved. Leaving that screen, a newer request, task cancellation, disabling or reset invalidates an older reply. A different screen's departure cannot cancel the current owner. Permission refusal cannot commit enabled preferences.

Enabled state, lock-screen details and quiet-hour edits save their field against the latest preferences before installing it or refreshing the scheduled request. Errors identify the failed setting and offer retry. Onboarding advances only after the current permission/checked-save outcome; a storage failure retains its step. Settings still offers Turn on when system permission is already allowed but saved check-ins are off. Restore invalidates pending enables and reloads the actual saved notes and reminder preferences.

An actual system permission change remains separate from a local preference save: granting permission followed by a failed preference write leaves Lumen's check-ins off. The app cannot roll back the system permission sheet. The current native probe verifies actual notification requests on a simulator, not delivery on a signed iPhone.

## Notification replacement

The existing policy allows at most one contextual, non-repeating request when current data suggests a useful action, quiet hours allow it, and current symptom/check-in state does not suppress it. Equal quiet-hour endpoints mean quiet all day. Lock-screen health details start off; generic private copy is the default.

Replacement removes pending notifications immediately, waits for an earlier add callback, and removes again before the latest addition. Superseded unstarted updates are skipped. If an older addition completes late, it is removed before later work finishes. Only the current successful callback records its target time. This prevents a late add from restoring a superseded detail-bearing request after check-ins are turned off or their content is changed.

Scheduling failure is separate from successfully saved preferences: **Your settings were saved, but the check-in couldn’t be scheduled. Try again.** The Retry check-in action retries scheduling. This queue is process-local. It is not a durable cross-termination delivery system, does not recall already delivered notifications, and does not establish physical-device background delivery.

## Storage boundaries

Unrelated legacy log/document persistence no longer rewrites personal-context or reminder preference files. The stores expose these preferences as read-only outside their checked mutation services. Legacy global reset remains a separate unchecked path; conversation/archive editing, other historical settings and whole-app erasure are not repaired by this batch. Actual disk exhaustion, power-loss durability, VoiceOver, live-provider privacy and release/distribution review remain open.
