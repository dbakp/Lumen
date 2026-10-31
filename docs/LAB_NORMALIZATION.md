# Reviewed lab units and test identity · Batch 24 verified

Batch 23 is published. Batch 24 extends the existing two-result comparison with an explicit reviewed unit conversion and test-identity decision. It must preserve the original results and existing literal comparisons. The full product goal stays active.

## Delivery contract

Keep each reported value, unit, test label/code, reference wording, collection day, source excerpt and provenance unchanged. A conversion belongs to the independent comparison snapshot. Display both original and converted numbers, the chosen source/target unit codes, exact conversion factor and the reason a conversion is unavailable. The existing exact-context comparison remains available without normalization. Unit changes reset review acknowledgement. Saving revalidates source fingerprints and the chosen result identities. Sharing starts off.

Provide reviewed source-unit assignments and a common target. Prefer an original FHIR UCUM code only when its system is exactly `http://unitsofmeasure.org` and the reviewed unit still corresponds to its original field. Codes and display labels are distinct. A proposed mapping for a printed micro sign must be shown and explicitly reviewed; never silently lowercase, remove punctuation or reinterpret an arbitrary abbreviation. A known supported reported unit cannot be remapped to a different magnitude. Unknown printed units may have an explicitly labelled user assignment; the app does not claim that assignment was verified by a terminology service. Retain the mapping basis and literal printed unit in the snapshot.

Test identity is separate from unit compatibility. Exact reported test names can retain their current meaning; differing names require a visible reviewed match or matching supplied coding identity. Preserve system/code/version tuples and distinguish original codes from a user's name match. Conflicting supplied codes cannot be overridden by a checkbox. Coding display text, property, method, specimen and laboratory are not interchangeable identities. Keep known context conflicts and original FHIR scalar/value-form rules blocking arithmetic. No analyte identity, molecular mass, mass-to-mole conversion, international/arbitrary-unit equivalence or clinical comparability is inferred from similar names or units.

Use a bounded on-device parser for supported linear case-sensitive UCUM expressions, including metric prefixes, multiplication/division, simple-unit integer powers, parentheses, positive integer factors and `10*`/`10^` scale atoms. Support common SI, volume, time, amount, concentration, count-density and catalytic-activity units. Unknown/nonlinear/arbitrary/annotated codes remain explicit unsupported input rather than being stripped or guessed. This supported subset is not a full UCUM-conformance claim. The amount-of-substance tag remains distinct from count even though UCUM's full canonical semantics can reduce mole to a count; no Avogadro-based conversion is offered here.

Bound codes to128 ASCII bytes,64 components,8 nested groups, simple exponents±24, dimension powers±64, prime-factor powers±1,024 and positive integer factors at most1,000,000,000. Reject the whole term on a bound or unknown atom; do not use a partial prefix. Apply operations left-to-right with equal precedence; a leading solidus inverts the first component. Do not accept a power on a parenthesized term, which the current UCUM grammar does not provide.

Conversion arithmetic uses exact signed decimal coefficients and rational unit factors. No floating-point scaling or rounded result may enter a snapshot. Withhold a nonterminating decimal, precision/range loss, qualified/nonnumeric value, source/value-form mismatch, same/unknown collection-day ordering or known duplicated event. References and flags stay literal in their original units; they are never converted into normal bands or interpretations. Preserve compatible optional typed normalization metadata through actual encrypted/readable backups, Markdown, retrieval and source-changed/deleted snapshot states. Existing snapshots and absent-metadata fingerprints must remain unchanged.

## Required verification and delivery

Test grammar/precedence/case, prefixes and powers, all supported atom definitions, dimensional conflicts, exact signed/zero/scientific conversion, rational cancellation/nonterminating values, precision/underflow/overflow, bounds and malformed inputs. Verify original-versus-reviewed FHIR code/unit provenance, manual mappings, conflicting coding, source freshness, duplicate events, acknowledgement reset and actual backup round trips. Exercise complete native selection/review/conversion/save/relaunch/source-change flows plus literal/error states, actual light/dark/largest text and375×667 keyboard/source/action containment. Use the supplied App Designer Pro skill and same continuing critic, at least two rounds; do not edit UI under review.

Build all products and unsigned Release, audit exact source equality, publish the coherent completed batch through the batch publisher and confirm GitHub main. After verification/publication and stopped workers, clear only task-owned obsolete output, keep compact evidence/current inputs/skill, and measure available-space change. Physical devices, VoiceOver, clinical validation, broader UCUM/terminology coverage, providers and release governance remain separate open work.

## Acceptance evidence · verified before publication

| Requirement | Evidence | State |
|---|---|---|
| Exact bounded grammar, quantity/fraction guards and finite arithmetic | LogicR12, all supported atom definitions, malformed/limit cases, sign/zero/precision and rational cancellation | Pass:1,227 checks |
| Separate reported values, original FHIR facts and reviewed assignments | LogicR12 correction, code/version conflicts, event identity and stale-source checks | Pass |
| Typed metadata and source preservation through actual backups | LogicR12 version-one, encrypted streamed and readable round trips | Pass |
| Reported/converted pairing, exact factors, snapshot-only name scope and plain native headings | Current normal/compact evidence and final critic; original/portable Markdown markers remain exact | Pass |
| All five simulator products and unsigned generic-iOS Release | BuildR10/ReleaseR2 exact manifests | Pass; unsigned only |
| Code/unsupported and source-change/removal/relaunch | NativeR2 scoped passes402.304s/506.423s in a mixed bundle; normal branch remains unchanged | Pass within stated scope |
| Actual375×667 editor, review/reset, save and relaunch | SmallR2/BuildR6,502.377s; normal-size branch unchanged | Pass |
| Dark/actualXXXL full selected labels, source review, editor/end caret, Save/completion | Current NativeR5/BuildR10,934.761s; all three identity choices | Pass |
| Full XXXL unit code/acknowledgement/switch containment | NativeR4/BuildR9,260.466s; unit-row layout unchanged by R10 menu repair | Pass |
| Same continuing independent critic | Four rounds40/55→43/55→41/55→43/55; final10/11 lines4+, no concrete defect | Done within scope |
| Final source audit |190 native/mirror,89 logic,188 Release inputs; fixture and158 original PNG hashes | Match |
| Coherent GitHub publication/read-back and scoped cleanup | Required after verified source/evidence commit | Pending |

Exact hashes, historical failures and source boundaries are retained in `Design/native/lab-normalization/verification.json`. NativeR1/R2 remain failed mixed bundles; later passing cases do not rewrite them. R7–R9 change test capture handling only. R10 fixes one accessibility selected-label layout; normal-size choices, unit rows and all numerical/model inputs remain unchanged. No source/UI edit follows final acceptance. These scoped results do not establish clinical validity, signed-device behavior, VoiceOver, complete UCUM/terminology coverage or release readiness.

## Primary references read 31 October 2026

- [UCUM2.2 specification](https://ucum.org/ucum): case-sensitive ASCII syntax, explicit products, left-to-right division, simple exponents and metric prefixes define unit expressions. Special and arbitrary units require their own semantics. This supports a bounded linear subset with explicit unsupported results; it does not validate Lumen's implementation.
- [NLM LOINC overview](https://www.nlm.nih.gov/oet/ed/healthdatastandards/02-530.html): test identities distinguish component, property, time, system, scale and method. Different display labels can refer to one code; matching dimensions alone do not establish the same clinical observation.
- [FHIR R4 Quantity](https://hl7.org/fhir/R4/datatypes.html#Quantity): display units and coded units are distinct fields. Retain their exact historical values beside reviewed assignments.
