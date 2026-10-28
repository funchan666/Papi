# Papi live feature acceptance

This is a preparation checklist, not a record of tests performed. Keep all
three runtime switches disabled until their applicable checks are complete.
Never delete, overwrite or reuse the existing device archive or real accounts.

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
