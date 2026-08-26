# Universal Coding Instructions v2 — Multi-Repo Product Ecosystem
### Battle-tested on TrashCash (5 apps + dashboard + shared Supabase), upgraded for TIMMA and every project after it
### Template target: **Flutter app (data-driven) + Admin Dashboard + Landing Page + shared Supabase backend**

> How to use: copy this file into every repo of the project as `CLAUDE.md` (mirror as `AGENTS.md`
> for other AI tools). Replace `[placeholders]`. Delete sections that don't apply to a repo but
> **keep the numbering** so cross-references survive. §0–§4 and §11 apply to every repo, always.

---

## §0. Prime Directives (non-negotiable, override convenience)

1. **Read before touching. Never invent.** If information isn't in the docs, code, or memory — read the file or ask which file to read. Guessing is a bug.
2. **The server is the only source of truth for money, prices, status, and permissions.** Clients render; they never decide.
3. **No magic strings, no literal UI text, no float currency, no hand-edited production schema.** Ever.
4. **Nothing is "done" until it ran on a real device/environment and the docs + memory say so.**
5. **Never deploy, publish, or mutate production without explicit owner approval in this session.**
6. **Write the plan to disk before the first code edit** — the context window can die mid-task; disk state must be enough to resume.
7. **Small stages; the project builds and runs after every stage.**
8. **When a cross-repo rule changes, change `ECOSYSTEM.md` first**, then the repos.
9. **Security and i18n are v1 features, not polish.**
10. **Delete dead code. Mirror existing patterns before inventing new ones.**

## §1. Ecosystem layout — one repo per deliverable, one canon for shared decisions

```
~/Desktop/Timma-eats/timmaeat-app-flutter/   # Flutter app (iOS + Android) — SCHEMA OWNER (supabase/migrations + functions)
~/Desktop/Timma-eats/timmaeat-webapp/        # Admin dashboard (Laravel or equivalent) + landing page + ECOSYSTEM.md
```
*(TIMMA instance: both repos live inside `~/Desktop/Timma-eats/` and local folder names match the GitHub repo names — `bej-hooj/timmaeat-app-flutter`, `bej-hooj/timmaeat-webapp`. Generic template: `~/Desktop/[Project]-App-Flutter/` + `~/Desktop/[Project]-Dashboard/`.)*

- **One repo owns the database schema.** All migrations live in the schema-owner repo. Every other repo only reads/writes existing tables — **never** alters schema.
- **`ECOSYSTEM.md`** (dashboard repo) is the canonical home for every decision spanning more than one repo: business rules, state machines, shared enums, payment/notification contracts, security canon. Other docs cite it as `ECOSYSTEM §n` and never redefine its content.
- Each repo carries the same skeleton:

| File | Purpose |
|---|---|
| `CLAUDE.md` / `AGENTS.md` | AI coding rules for this repo (this file) |
| `PROJECT.md` | Product scope, screens, business rules for this repo |
| `BUILD_PLAN.md` | Living progress log: done / next / current stage |
| `DEPLOY.md` | How to deploy (server, paths, commands) — running it needs explicit approval (§9) |
| `docs/INDEX.md` | Table of contents of all docs |
| `docs/<feature>-<date>.md` | One plan + results doc per feature/session |
| `docs/architecture/database-schema.md` | (schema-owner only) authoritative table reference |
| `docs/setup-config.md` | Every manual credential/console step (Firebase, APNs, keys, DNS) |

## §2. Session protocol — how every working session runs

1. **Read first**: `CLAUDE.md`, `PROJECT.md`, `BUILD_PLAN.md`, relevant `docs/` files, AI memory, and `ECOSYSTEM.md` when the task touches shared rules. No results before reading.
2. **Plan to disk before code.** Record in `docs/<feature>.md` **and** memory: goal, files to touch, data contract, test plan, how-to-resume notes.
3. **Staged passes.** After each stage the app builds and runs. Sync `BUILD_PLAN.md` + feature doc + memory at every pass end, so a fresh session continues from disk alone.
4. **Mirror before creating.** Find the closest existing file; copy structure, naming, idioms.
5. **One file at a time** on large refactors; confirm before moving on.
6. **Reference implementation wins.** When one side is authoritative (dashboard defines a contract the app consumes), read it first, port conservatively.
7. **Context budget awareness.** If the task won't finish, produce a self-contained continuation prompt: current state, exact next steps, file paths, device/test setup, open bugs.
8. **Verify claims.** Never state "this works" without having built/run it this session; otherwise say "written, not yet verified".
9. **Definition of done**: all sub-tasks done · built clean · tested on real device (emulator only as fallback) · logs checked at every layer · related bugs fixed · docs + memory reflect the real state · committed + pushed · deployed only with explicit owner approval.

## §3. Architecture rules — constants-driven, single source of truth

- **No magic strings, anywhere.** Table/column/RPC/route/notification/status/storage-key/deeplink values are constants:
  - Flutter: `lib/core/constants/` (`DbTables`, `DbColumns`, `RpcNames`, `EdgeFunctions`, `NotificationTypes`, `AppRoutes`, `StorageKeys`).
  - Laravel: `app/Support/` constant classes; `route(RouteNames::X)` — never a bare string.
- **No hardcoded user-facing text.** Flutter ARB (`intl`) with runtime locale switch re-keying the root widget; Laravel `__('key')`; landing localized. Default locale `[fr]`, secondary `[en]`, both complete at every release.
- **Shared enums defined once** in `ECOSYSTEM.md` + schema, mirrored as constants with identical literal values everywhere. A drifted enum literal is a release blocker.
- **Data-driven from the dashboard.** Any content ops can change (menu, prices, zones, banners, FAQ, toggles) lives in DB tables with `published`/`active` flags, dashboard CRUD, app repository + cache. Content changes never require an app release.
- **Repositories before real network.** `abstract class XRepository` + `MockXRepository` + `SupabaseXRepository`; screens depend on the interface; mock ships first.
- **State machines live in the database** (status enums + transitions enforced in RPCs), not in client `if`s.
- **Money is integer minor units** (`int` XAF/FCFA) in Dart, PHP, JS, SQL, Blade. One formatter per codebase. Float currency = review-blocking bug.
- **One display timezone constant** (`[Africa/Douala]`); storage UTC; day-boundary/slot math in exactly one utility per codebase.
- **Split large files** into focused classes; **delete dead code**; no backwards-compatibility hacks.

## §4. Database & backend rules (Supabase or equivalent)

- **Versioned migrations only**, schema-owner repo, `YYYYMMDDHHMMSS_description.sql`. Never alter production by hand. Every migration is forward-only and idempotent-safe to re-run in dev.
- **Sensitive writes go through RPCs, never direct table writes**: order placement, status transitions, payments confirmation, refunds, balances, claims. RPCs are `SECURITY DEFINER` with `set search_path = ''`; admin/service-only RPCs get `revoke all` from `anon`/`authenticated`.
- **Server-side pricing/authority**: clients send IDs + quantities + selections; the RPC recomputes prices from published rows, validates business rules (mode/payment matrix, zones, slots, promos), and **snapshots** names/prices/selections into order lines. Client-sent totals are ignored.
- **Concurrency by design**: first-accept-wins enforced in the RPC (`WHERE status = 'expected'` + row lock), never in the client.
- **RLS on every table, deny-by-default**; app uses anon key + RLS; dashboard uses service credentials server-side only, and still calls the same RPCs for sensitive writes.
- **Idempotency everywhere money moves**: unique idempotency keys on payment attempts; webhook processing idempotent; at most one `success` per order (partial unique index).
- **Webhooks**: verify signature/hash → **re-verify via the provider's status API** (never trust the webhook body alone) → store raw payload → respond 200 fast → process idempotently. A webhook log table keeps every inbound call for audit.
- **Poller fallback** (cron) behind every webhook-driven flow — webhooks get lost.
- **Edge functions** hold server secrets (provider keys, `ADMIN_SECRET`, `CRON_SECRET`, service JSON) via the secrets manager — never committed. Shared logic (push, formatting, provider adapters) in `_shared/`.
- **Push — dual-platform FCM v1 payload recipe** (hard-won): top-level `data` only (Android routes via `onMessageReceived`, own channel) **plus** `apns` block with `aps.alert` + `sound` (iOS shows nothing on data-only; missing APNs `.p8` = 401 `THIRD_PARTY_AUTH_ERROR` — check function logs first). `android.priority: high`, `apns-priority: 10`.
- **Every push has an in-app twin** row in `notifications`; realtime updates the badge; inbox works without push.
- **Launch routing is cache-first with a bounded network wait** — never stuck on splash offline.
- **Realtime is the fast path; REST reload on foreground/reconnect is the source of truth.**
- **Indexes with the query**: any new hot query ships with its index and an `EXPLAIN` check in the feature doc. Indexed/unique VARCHAR ≤ 191 where MySQL-compat matters; FKs declared in migrations.

## §5. Flutter app rules

- **Flavors** `dev`/`prod` via `--dart-define`/flavor config; keys and URLs from build config, never hardcoded. `docs/setup-config.md` records every manual step (Firebase registration, APNs upload, SHA fingerprints, tokens).
- **One state solution** (Riverpod **or** Bloc) everywhere; screens dumb; logic in controllers/notifiers; data in repositories.
- **i18n** per §3; **money/time** per §3.
- **Push**: `firebase_messaging`; on launch **and every foreground**, fetch the FCM token and upsert to the profile row (never rely only on the refresh callback — fixes "pushes go to the last device"). Log authorization status in debug (`[PushDiag]`-style temp logs, stripped after).
- **Permissions at the moment of need**, with a one-line rationale UI.
- **Offline**: every list renders cache first, then refreshes (`updated_at` watermark). Explicit offline banner; no silent staleness.
- **Async money UX**: payment-pending screens own a countdown, realtime listener, manual refresh, retry/switch paths — and never declare success client-side.
- **Navigation via route constants** (`go_router` or equivalent); deeplinks declared centrally.

## §6. Dashboard rules (Laravel reference — TIMMA uses Laravel 13; adapt to your stack)

- Blade + Livewire + Alpine + Tailwind; **controller → service → view**; services own all business logic; Livewire components stay thin.
- Route names, enums, notification types as constants; translations for all UI text; semantic HTML.
- **Never write financial/status data directly — call the same RPCs the apps use** (service credentials, server-side).
- **Per-module log channel** (`storage/logs/<module>/`) and per-module documentation (`storage/Project_Documentation/<Module>/` — controller ↔ service ↔ view map), updated with each feature.
- The dashboard is the **content editor**: every data-driven app surface has a CRUD module with publish/unpublish, ordering, and an **app-faithful preview**.
- Ops screens (live boards) use short polling (≤ 5 s) with cheap indexed queries first; upgrade to realtime only when measured need.
- Role gates on routes **and** in services (defense in depth); an access matrix lives in `PROJECT.md` and is tested (§14).

## §7. Landing page rules

- Shares **design tokens** (colors, typography, spacing, radii) with the app — exported from one `design-tokens` file both sides read.
- SEO first-class: semantic HTML, unique titles + meta descriptions, canonical URLs, OpenGraph/Twitter cards, sitemap, robots, hreflang, JSON-LD where a type fits; fast LCP (no blocking scripts, optimized/responsive images, full-page cache).
- Marketing content (pricing, menu, FAQ, testimonials) reads from the same published content tables the dashboard edits — the landing never hardcodes prices.
- i18n from day one in bilingual markets; legal pages (privacy, terms/CGV) live here — **app-store submission depends on them**.

## §8. Testing & verification discipline

- **Real devices first**: Android via Android Studio, iOS via Xcode; emulator/simulator only as fallback.
- iOS from CLI: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; build `xcodebuild -destination 'id=<udid>'`; install/launch `xcrun devicectl device install app` / `process launch --console` (console output buffers when piped — write straight to a file; app args need `--`).
- **Watch logs at every layer** when debugging: app console → edge/function logs → API/REST logs → database rows. Prove each hop before blaming the next.
- After any fix: rebuild, reinstall, re-run the **end-to-end smoke** (not just the changed unit), record results in the feature doc.
- Keep `docs/verification-<date>.md` (or a results section) with exact smoke steps so anyone can re-run them.
- **Chaos drills for money paths**: at least once before launch — kill the webhook (poller must recover), double-fire the webhook (idempotency must hold), attempt a client price tamper (server must reject), go offline mid-payment (UX must survive).

## §9. Deployment discipline

- **NEVER deploy (VPS, edge functions, store builds) without explicit owner confirmation** — even if the prompt implies it. `DEPLOY.md` documents the workflow; running it is a separate approved action.
- Migrations and functions deploy via CLI with version notes; verify immediately in production logs; record the deployed version in `BUILD_PLAN.md`.
- Store submissions: maintain `APPLE_STORE_REQUIREMENTS.md` / `PLAY_REQUIREMENTS.md` (privacy strings, background-mode justifications, data-safety forms, version/build bump rules, screenshots).
- Never run mutating "tests" against production data outside a transaction — and know your tools: some SQL consoles do **not** honor begin/rollback.
- Staged rollouts for app releases (Play staged %, TestFlight first); a written rollback step for every deploy.

## §10. AI memory & docs upkeep (cross-session continuity)

- One memory directory per repo (`~/.claude/projects/<repo-slug>/memory/`): `MEMORY.md` is a one-line-per-fact index; each fact its own file with frontmatter (`type: user|feedback|project|reference`).
- Save: device IDs and build commands, credential/setup steps, working-style agreements, feature state (`ACTIVE/DONE + what remains`), gotchas ("xcodebuild needs DEVELOPER_DIR", "console buffers when piped", "provider X returns empty responses — retry").
- Convert relative dates to absolute. Update or delete stale memories; never duplicate what repo docs record — memory points at them.
- End every session by syncing: `BUILD_PLAN.md` (stage status), the feature doc (results), memory (state + how to resume).

## §11. Security baseline (applies to every repo, every session)

1. **Secrets policy**: secrets only in secret managers / server env; never in git, client bundles, logs, or docs. Rotating a leaked key is step 1, not step 3. `.gitignore` audited at repo creation.
2. **Client trust = zero**: pricing, totals, status transitions, role checks, eligibility rules are computed/enforced server-side (§4). UI checks are UX, not security.
3. **RLS checklist** per new table (enforced in review): RLS enabled? policies for each verb? tested as anon, as another user, as owner? admin path via RPC not policy loophole?
4. **Webhook hardening** per §4: signature/hash → status-API re-verify → idempotent processing → raw payload retained.
5. **Auth/OTP abuse**: provider fraud protection ON (e.g. Twilio Verify Fraud Guard), attempt rate limits, CAPTCHA on OTP request, geo-permissions restricted to operating countries. SMS pumping is a financial attack — treat it as such.
6. **PII minimization & access**: collect only what the product needs; least-privilege roles; no PII in logs; private buckets + signed URLs for documents (receipts, exports).
7. **Input handling**: validate type/size on uploads; parameterized queries only; escape all rendered user content.
8. **Dependency hygiene**: `flutter pub outdated` / `composer audit` / `npm audit` at every release; pin versions; upgrade deliberately, not accidentally.
9. **Auditability**: who did what — staff actions on money/status write actor + reason to an audit trail.
10. **Kill switches**: every externally-driven feature (payments provider, delivery mode, promo engine) has a server-side off switch that doesn't need a release.

### §11.11 Zero Trust Code Generation (owner directive, 2026-08-26)

**Canon lives in `ECOSYSTEM.md` §16.8** (§0.8: a cross-repo rule changes there
first). This is the working copy every repo carries.

Rules 1–10 above already cover secrets, zero client trust, RLS, webhooks, PII,
input handling, dependencies, auditability and kill switches. What follows is
the part that was **not** written down anywhere, stated so it can be checked
rather than assumed:

1. **Secrets, per platform, named.** Android `EncryptedSharedPreferences` /
   KeyStore; iOS Keychain Services; public identifiers and endpoints from build
   configuration (`--dart-define`, `BuildConfig`, `Info.plist`) and never a
   literal. Server: `env()` only, and never a value that survives
   `config:cache` into a committed file.
2. **Hashing: Argon2id or bcrypt** with a real cost factor. Never MD5, SHA-1 or
   a plain SHA-256 — a fast hash is the wrong tool for a password whatever its
   output length.
3. **At rest: AES-256-GCM** for anything sensitive stored locally.
4. **Transport: HTTPS / TLS 1.3** everywhere; certificate pinning or a platform
   network-security configuration where a surface warrants it.
5. **Every entrance is untrusted**, and the list includes the ones that do not
   look like network I/O: deep links, intent extras, IPC, QR payloads, and **a
   row an operator typed into the dashboard**. Validation is server-side and
   typed (`FormRequest`, or a typed parse on a client).
6. **Parameterised queries only.** No string-concatenated SQL, ever.
7. **Escape by default** (`{{ }}`). `{!! !!}` requires an explicit allow-list
   control, and the control must be *checkable* — a comment asserting the input
   is trusted is not one.
8. **Authorization is per-resource.** A policy or gate on every route that
   touches a resource; `Auth::check()` alone is not authorization. CSRF
   middleware on every state-changing endpoint.
9. **`$fillable` allow-lists** on every Eloquent model. **Never
   `protected $guarded = []`.**
10. **No stack trace, schema or internal path** reaches an end user in
    production; PII, tokens and card data are redacted from log lines.
11. **Self-audit against the OWASP Top 10 (API + Web) before shipping.** Where
    a secure pattern is skipped for brevity, write the production alternative
    down rather than leaving the gap silent.

⚠ **A protocol nobody has run is decoration.** The first audit (2026-08-26,
recorded in ECOSYSTEM §16.8-a) found no `$guarded = []` and no concatenated
SQL — and one real hole, where *measuring beat assuming*: the staff docs render
through `{!! !!}`, and `Str::markdown` escapes `<script>` and `<iframe>` while
happily rendering `<img src=x onerror=…>`, `<svg onload=…>` and
`[x](javascript:…)`. Closed at the converter and by a test that fails the build
if a docs file grows an event handler. Run the audit; do not assume it.

## §12. Performance budgets (set at project start; measured, not vibed)

- **App**: cold start → interactive `[< 2.5 s]` on a mid-range Android; primary lists 60 fps (virtualized, `const` widgets, no sync I/O on build); images sized to slot via CDN transforms + cached; payloads paginated (`[≤ 50]` rows/page); cache-first screens render instantly offline.
- **Web/landing**: LCP `[< 2.5 s]`, CLS `< 0.1`, INP `< 200 ms`; full-page cache; responsive images; zero render-blocking third-party scripts.
- **Backend**: hot queries `[< 50 ms]` with indexes shipped alongside (§4); N+1 banned (eager-load or batch); ops boards' polling queries measured under load.
- Budgets live in `PROJECT.md`; a release that regresses a budget needs an owner decision, not a shrug.

## §13. UI/UX standard (design is a requirement, not decoration)

1. **Design tokens** (one source, §7): color roles (not raw hexes in code), type scale, spacing on an **8pt grid**, radii, elevation. Both light contexts consistent; dark mode only as a deliberate, complete project.
2. **The state triad — loading / empty / error — is mandatory on every async surface**: skeletons (not spinners) for lists, empty states with a friendly line + CTA, errors that are human, localized, and retryable. "It just shows nothing" is a bug.
3. **Touch & feedback**: targets ≥ 48dp; visible pressed states; haptics on key confirmations (add-to-cart, payment success); optimistic UI only where a rollback is implemented.
4. **Motion**: 200–300 ms, ease curves, purposeful (hierarchy, continuity); no gratuitous animation on hot paths.
5. **Accessibility**: contrast ≥ 4.5:1 for text, semantic labels on interactive elements, dynamic-font tolerance checked on the 3 densest screens, forms navigable by keyboard (web).
6. **Content style**: sentence-case, concise, localized; numbers/dates/money via the shared formatters; destructive actions confirm with the consequence stated.
7. **Perceived speed is a feature**: cache-first render, background refresh, progress with time hints on long waits (payment countdowns), never a frozen screen.

## §14. Testing pyramid (density follows risk)

- **Dense unit coverage where money and rules live**: price computation, promo math, VAT extraction, money formatter, slot/day-boundary math, state-machine transition guards. These suites run in CI on every push.
- **RPC/integration tests** against a local/shadow database: place-order happy path + every rejection rule (matrix, zone, min-order, sold-out, tampered price), payment confirm idempotency (double webhook), refund recording.
- **RLS tests**: for each table, assert anon/other-user/owner access as designed.
- **Widget/component tests** for the trickiest UI logic (composer min/max rules, combo stepper, payment-pending state handling).
- **Contract tests with recorded fixtures** for provider webhooks (success/failure/duplicate/garbage payloads).
- **E2E smoke per release** (manual is fine, scripted steps in `docs/verification-*.md`): one order per mode per platform, one failed payment, one refund, one 86-toggle reflected in app.
- A bug fixed twice gets a regression test the second time, no exceptions.

## §15. CI/CD & observability

- **CI on every push** (GitHub Actions or equivalent): format check, static analysis (`flutter analyze`, `larastan`), unit tests, build (app: debug build; dashboard: composer install + tests). Red CI blocks merge.
- **Migration safety job**: apply all migrations to a scratch database from zero — catches ordering/typos before they touch shared envs.
- **Crash & error tracking from S0**: Crashlytics/Sentry (app), Sentry/log alerts (dashboard, edge functions). Releases tagged so crashes map to versions.
- **Structured logs with context** (order_id, payment_id, user hash) at every money hop; per-module channels (§6); retention decided, not accidental.
- **Alerting on the money path**: webhook failures, poller catching what webhooks missed, reconciliation orphans → notify the owner channel daily/immediately per severity.
- Environments: `dev` (free to break) → `prod`; no shared "staging-that-is-actually-prod".

## §16. Versioning & release discipline

- **Conventional commits** (`feat:`, `fix:`, `chore:`…) — enables changelogs and bisecting; one logical change per commit; no "wip" on main.
- **SemVer** for the ecosystem contract: breaking a shared enum/RPC contract bumps major in `ECOSYSTEM.md`'s version header and requires a coordinated migration note.
- **App versioning**: `version+build` bumped every store upload; `CHANGELOG.md` per repo, human-readable, updated at release, not after.
- **Release checklist per repo** (kept in `docs/release-checklist.md`): budgets §12 pass, smoke §14 pass, translations complete, store requirement files current, rollback step written, owner approval recorded.
- **Feature flags over long-lived branches**: ship dark, toggle live (`loyalty_enabled` pattern); flags are settings rows, removable once stable.

---

*v2 changelog vs v1: added §0 Prime Directives; §2 gained context-budget + verify-claims rules; §4 gained server-side pricing, idempotency, webhook re-verification, poller-fallback, index-with-query; new §11 Security, §12 Performance budgets, §13 UI/UX standard, §14 Testing pyramid, §15 CI/CD & observability, §16 Versioning & release. Original session protocol, memory system, and repo skeleton preserved intact.*
