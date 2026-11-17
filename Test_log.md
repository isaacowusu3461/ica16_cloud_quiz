# ICA16 Class A — Test Log

Student: Isaac Owusu
Course: CSC 6360 — Mobile App Development
Date: November 16, 2026
Platform: Flutter / Android emulator (Apple Silicon development machine)
Firebase: Authentication and deployed Cloud Firestore
Test timestamps: November 16, 2026; exact per-test times not recorded for every test

The observations below are based on the user-confirmed test results and the supplied screenshots. Missing console logs, exact test times, and commit hashes are not invented.

| ID | Precondition / action | Expected result | Observed result | Evidence | Status |
|---|---|---|---|---|---|
| T01 | Valid and invalid Firebase sign-in | Correct UID or visible error; no secrets | User confirmed pass; authentication UI tested | Confirmed; no screenshot reference assigned | Passed (user-confirmed) |
| T02 | GET exact Class A OpenTDB request | 10 easy category-9 MCQs | User confirmed pass; ten-question quiz loaded | Confirmed; no screenshot reference assigned | Passed (user-confirmed) |
| T03 | Bad JSON, nonzero code, nine results | Reject each response; controlled retry | User confirmed formal T01–T05 tests passed; individual trace not supplied | Confirmation only; attach debug logs if required | Passed (user-confirmed) |
| T04 | Correct, incorrect, double tap | Decoded text, stable choices, one score change | User confirmed pass | Confirmation only | Passed (user-confirmed) |
| T05 | Finish and replay | 10 review entries; reset; new ID | User confirmed pass | Confirmation only | Passed (user-confirmed) |
| T06 | Online submit; double tap | One document; server timestamp; server-only verification | User reported successful cloud verification | Screenshot: 8.00.58 PM | Passed (user-confirmed) |
| T07 | Restart and retrieve same ID | Original record returned by server | Verified existing attempt, score 3/10, ID suffix G8iIGTZX | Screenshot: 8.00.58 PM | Passed (user-confirmed) |
| T08 | Offline submit, reconnect, recover | No false success; same-ID recovery | saveUnknown, server notFound, manual retry, cloudVerified | Screenshots: 8.17.36 / 8.18.32 / 8.18.50 PM | Passed (user-confirmed) |
| T09 | Suppress ack after real transaction | saveUnknown then server-confirmed existing record | Recovery verified committed attempt, ID suffix QzcSL | Screenshots: 8.33.29 / 8.35.00 PM | Passed (user-confirmed) |
| T10 | Cross-user read and write | Both permission-denied | Both operations denied by deployed rules | Screenshot: 9.05.24 PM | Passed (user-confirmed) |
| T11 | Score 11, extra field, update | All rejected; original preserved | All checks passed, original score and timestamp intact | Screenshot: 9.20.31 PM | Passed (user-confirmed) |
| T12 | Simulate unavailable/resource-exhausted | Distinct errors, no false success, manual recovery | Both simulations and recovery passed | User confirmation; no extra screenshot | Passed (user-confirmed) |
| G01 | Concurrent same-ID same-score submissions | One matching cloud document | Preliminary same-session test and later two-client verification reported passed | User confirmation; client traces not attached | Passed (user-confirmed) |
| G02 | Same ID, different score | Collision; original intact | Four checks passed: collision, score, timestamp, schema | User confirmation; no extra screenshot | Passed (user-confirmed) |
| G03 | Delayed response after auth switch | Old response cannot update new user | Controlled UID-gate test passed; later end-to-end verification reported passed | User confirmation; no extra screenshot | Passed (user-confirmed) |

## Redacted record references

- T07: previously saved round, suffix `G8iIGTZX` (check exact suffix against screenshot before submission).
- T08: offline/recovery round suffix `g67SLU6`.
- T09 / T10 / T11: saved attempt suffix `QzcSL`.
- Firestore path: `users/{authenticatedUid}/attempts/{roundId}`. Never publish passwords or full auth tokens.

## State transitions

`playing -> readyToSubmit -> submitting -> verifying -> cloudVerified`

`submitting -> saveUnknown -> verifying -> cloudVerified` (commit already exists)

`submitting -> saveUnknown -> verifying -> notFound -> readyToSubmit -> submitting -> verifying -> cloudVerified` (no prior write)

`submitting -> collision / permissionDenied` (do not overwrite)


