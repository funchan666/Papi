# Papi: real backend migration

Keep the current SwiftUI experience and existing Keychain archive intact until each server operation succeeds. The production Supabase project is `cquoffowtjnxmgaxavym` in `us-east-1`.

- [x] Inspect the current local archive, social actions, StoreKit settlement, media and policy publication.
- [x] Create the Supabase project in the selected organization.
- [x] Enable guest sign-in after the requested console confirmation.
- [x] Add the pinned Supabase Swift dependency and a Keychain-backed client with explicit guest identity checks and community, media and wallet operations. These operations are not yet called by the app's screens.
- [ ] Retain the guest session securely and provide identity linking before sign-out can discard recovery credentials; add sign-up abuse protection before release.
- [ ] Deploy and inspect database permissions for profiles, follows, consent-based friendship, moderated posts and comments, messages, reports and blocks. A message requires mutual following and no block on either side.
- [ ] Replace local social reads and writes with authenticated server operations; do not present bundled editorial profiles, conversations, room participants or gifts as live user activity.
- [x] Create private `coffee-media` storage with owner-only upload/read/delete rules and a 50 MB object limit.
- [x] Add a read policy for media attached to approved moments, subject to the viewer's post visibility.
- [ ] Upload user media to ownership-protected storage, subject to moderation; provide approved-media delivery and preserve local drafts and files until confirmed upload and migration.
- [ ] Implement an operational moderation queue and support contact, including report review and account removal; update and publish both policies to describe actual data handling.
- [x] Make login and Settings open the same published H5 agreements without a bundled policy-text fallback. The existing public pages remain the local-edition policies until the actual cloud behavior is complete.
- [x] Create a server-owned 800-coin welcome grant and atomic, idempotent recipe-unlock operation. The app still uses its local wallet and is not connected to these operations.
- [x] Add a server-side moment submission operation that checks media ownership, charges once and creates a pending post in the same transaction. It is not connected to the app or an operational moderation process.
- [x] Add server-side likes and bookmarks for approved visible posts.
- [ ] Make the server authoritative for all spending and verified Apple transactions; the user reports there are no prior real paid users, but local records must still be preserved and reconciled without double-crediting.
- [ ] Integrate real audio/video using LiveKit, with server-authorized room credentials; the user will provide its configuration later. Supabase Realtime alone does not carry media.
- [ ] Review deployed schema and security advisors; statically inspect the project and changes. Build, device, runtime, payment and network acceptance remain separate and require explicit authorization.

Do not clear a local snapshot, credit local purchase history to the server, mark a post approved, or consume a StoreKit transaction until the corresponding ownership and completion are confirmed. The checkout product IDs and prices remain unchanged.

As of 2026-10-27 the app's screens still use local data; the new client is not wired into login or actions. The existing published agreement explicitly excludes online accounts, so policy publication and renewed consent must precede any user-data transfer. The Supabase security advisor flags guest access policies; these are expected for the chosen guest sign-in and still need adversarial permission checks. Direct post inserts are disabled; the submission operation charges and creates pending content, but there is no operational review workflow yet. Approved media has a protected read policy, but the app does not load it yet. The current schema and SQL are a foundation, not a production release.
