# Follow-up source finding · general notice eligibility

Batch40's personal-context notices explicitly set `lastReplyCanBecomePlan = false`. Preserve that verified behavior.

The broader coach still defaults this flag to true before search. Several Library/search-setting failure returns leave that default in place. `CoachView` tests the flag plus the user's plan intent when retaining the reply, and `PlanBuilder.steps` supplies two generic steps when text has no numbered or bulleted actions. Source inspection therefore identifies a separate route by which a general search/change notice could become an automatic Library plan. This has no controlled runtime reproduction yet and is not an accepted behavior or a Batch40 regression claim.

In a subsequent coherent repair, make success versus notice/error eligibility explicit for every coach return. Hold a Library-referenced response, change or withdraw the selected record, release it, and verify the factual visible notice, saved conversation packet and absence of an automatic plan copy. Exercise failed search/settings changes and retain ordinary local/model plan behavior. Keep manual Save to Library available and preserve prior saved plans. Do not infer safe eligibility from prose matching.

This remains part of the full product goal, alongside the already-declared durable Health save/delete intent and identity-preserving acknowledged Watch delivery. It does not replace their scope or close the device/provider/clinical/accessibility/distribution gates.

## Related source-only dispatch finding

`ChatCoachService.reply` validates selected Library passages and the search lease before calling `AIService.chat`, then validates them again when the reply returns. `LLMClient.preparedCoachChat` may await credential-route resolution between those checks; its new post-resolution guard covers the captured personal-context revision only. A Library record or search setting could change during that wait while the previously prepared source/history packet remains captured. This has not yet been reproduced with a controlled held route and is not covered by Batch40's personal-note acceptance.

Before claiming a complete consent boundary, declare and exercise the Library/search authorization policy through that same wait: withdraw or edit a selected record, change the search lease, and separately change any referenced historical source. Inspect actual outgoing packets as well as returned notices. Keep ordinary unchanged requests working. A post-response rejection alone cannot undo a request already submitted.
