# Papi live feature acceptance

This checklist includes a scoped record of isolated checks below. Keep all
three runtime switches disabled until their applicable checks are complete.
Never delete, overwrite or reuse the existing device archive or real accounts.

## Isolated checks on 2026-10-28

- The iOS Simulator build succeeded for both simulator architectures. A newly
  created iPhone Duo simulator launched the app and displayed its onboarding.
  An earlier unsigned launch encountered Keychain error -34018; a later Xcode
  ad-hoc build reached onboarding, but this does not establish that Keychain,
  login or other flows work. No physical-device or real-signing validation was
  performed.
- Disposable PostgreSQL 17.10 fixtures exercised the actual deletion, voice,
  call and guard SQL alongside mocked Auth and Storage schemas. They covered
  ownership, consent, cancellation, pending purchases, retry receipts,
  attachment retention and both transaction orders for deletion against
  messages, call requests, reactions/comments, voice joins, uploads and order
  creation. Several unrelated tables are stubs; this is not full Supabase RLS,
  service API, payment settlement or cross-device acceptance.
- A loopback-only LiveKit 1.13.11 server carried synthetic audio and video
  between two isolated participants and removed participants successfully.
  This used Node clients rather than the Swift app, and did not exercise real
  microphones or cameras. Self-hosted LiveKit cannot validate the Cloud-only
  token-revocation behavior; test that separately before activation.
- In a disposable PostgreSQL fixture, the actual Apple-order settlement SQL
  blocked deletion while a pending settlement was uncommitted and did not
  double-credit a repeated settled transaction after deletion began. These
  were synthetic orders, not Apple sandbox or refund validation.
- The actual deletion and cleanup Edge handlers were exercised with fake
  clients and no network access. Deletion covered concurrent receipt recovery,
  owner mismatch, invalid receipts, failed Storage deletion and resuming after
  a failed final database acknowledgement. Cleanup covered ticket rejection,
  both call participant removals, voice removal, partial failures and invalid
  jobs. Deletion handler version 4 and cleanup handler version 2 were deployed
  and read back; the production activation gates remain disabled. These mocks
  do not establish real Auth, Storage, scheduler or LiveKit Cloud behavior.
- The token handlers were run locally with the pinned LiveKit SDK and fake
  Auth/RPC clients: room identities and grants, 120-second token lifetime,
  authorization rechecks and rate limits passed. The Swift client now accepts
  only the configured LiveKit host for both voice and calls; a simulator build
  succeeded after this change. No token was sent to a real LiveKit server.
- The scheduler SQL was exercised with a fake pg_net sink in a disposable
  PostgreSQL database: idle behavior, wake on pending work, ticket expiry and
  concurrent single use, concurrent call batches and voice queue rotation
  passed. This does not verify hosted pg_cron/pg_net timing or actual delivery.
- Further PostgreSQL fixtures exercised both orderings of voice join versus
  blocking, repeat cleanup of an earlier voice session after a new join,
  accepted-call versus unfollow, 20-person room capacity, stale heartbeat
  cleanup and the voice/call runtime disable switches. These checks use local
  transactions and do not prove LiveKit Cloud participant removal or device
  behavior.
- The voice and call token functions now return a retryable error when Auth
  fails unexpectedly; cleanup does the same when ticket verification cannot
  reach the database, and still rejects an invalid ticket. Local mocked error
  checks passed. Both token functions and the cleanup function were deployed
  as version 3 and read back. Deno 2.9.6 type-checked these three functions
  and deletion version 4; this is not a hosted end-to-end test.
- A disposable PostgreSQL fixture applied the complete draft RPC guards and
  checked all 27 guarded operation signatures against both deletion-pending
  accounts and revoked sessions. A separate fixture exercised eight actual
  read RPCs with the draft RLS rules: each returned expected fixture data
  before revocation and hid it after session revocation or deletion start.
  These draft policies are not deployed and the tests do not substitute for
  real Supabase Auth/Storage or full business-operation acceptance.
- Read-only catalog comparison found the 27 draft wrappers match the existing
  production RPCs' argument and return types, volatility and invoker status;
  production grants currently allow authenticated and deny anon. This is a
  signature/privilege comparison, not proof of complete behavior or approval
  to enable the draft migrations.
- Supabase rejected creation of a disposable branch on the current plan; no
  upgrade was purchased. The production gates and cleanup schedule remain off.

## Preparation

- Use a disposable Supabase environment with its own Auth users, private
  Storage bucket and Edge Function secrets. Check any branch or project cost
  before creating it. A production checkout or production database is not a
  substitute for this isolation.
- Use separate LiveKit test credentials and uniquely named test rooms; never
  include credentials, JWTs, deletion receipts or personal data in logs.
- Apply the necessary schema and functions in migration order. The account
  deletion policy and RPC drafts require an explicit lock-order review before
  applying them, including direct likes, comments and Storage operations.
- Verify test-environment settings and secret names without printing values.
  Confirm no production runtime switch or cleanup schedule has changed.

## Voice rooms

- Join using two test accounts, enable and mute a microphone, and verify that
  the displayed participants correspond to the live session.
- Block one participant while both are connected. Confirm participant removal,
  token revocation and refusal of a delayed reconnect; test both block orders.
- Interrupt joining before and after the server response, retry exit, and then
  rejoin with a new session ID. A delayed cleanup for the old session must not
  disconnect the new one.
- Exercise disabled-runtime cancellation, expired heartbeats, duplicate cleanup
  invocations, rate limits, network failure and worker retry. Verify that the
  cleanup queue drains and no room exceeds the configured participant limit.

## Calls

- Verify that only mutually following users can request a call, that only the
  intended recipient can accept or decline, and that neither microphone nor
  camera starts before the user's explicit choice and system permission.
- End, block, unfollow, time out and lose connection during a call. Confirm
  that both participants are disconnected and old tokens cannot reconnect.
- Exercise caller retry, recipient retry, cancellation while a request is in
  flight and multiple cleanup workers. Foreground call notices are separate
  from background push and CallKit, which are not configured.

## Account deletion

- Seed only disposable users with owned files, messages sent by other users,
  active voice/call sessions and purchase-order fixtures. Capture the expected
  state before starting; never use a real account or real Apple transaction.
- Verify that pending purchases prevent deletion and remain intact. Verify that
  starting deletion closes live sessions before Auth or Storage removal.
- Retry after interrupted responses, repeated requests and expired sessions.
  Check that the same Keychain receipt resumes the original operation and that
  a different receipt cannot adopt it.
- Verify that only the deleted user's own Storage files are removed. Sender-
  owned attachments from messages to that user must be recorded in the private
  retention manifest and remain untouched until a retention policy is defined.
- Confirm the completed receipt no longer retains the deleted account ID, old
  access tokens cannot read or write user data, and the test device's existing
  local archive remains preserved.
- Exercise concurrent deletion against messages, follows, calls, voice joins,
  uploads, likes, comments, purchase settlement and repeat RPC requests. Any
  failure, deadlock, orphan or uncertain outcome blocks production activation.

## Production activation prerequisites

Review retention and refund handling, publish the online policies with the
operator's contact details, collect the necessary consent, and complete any
Apple-specific configuration. Review the separate user-facing deletion RPC,
RLS and lock migrations together. Enable the cleanup worker and each runtime
switch only after its own isolated and device acceptance; record the verified
versions and rollback procedure. Keep the existing local data until the entire
cutover is complete.
