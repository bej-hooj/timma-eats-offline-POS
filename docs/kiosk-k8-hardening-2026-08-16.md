# K8 — kiosk hardening

Plan of record: `docs/pos-kiosk-kds-offline-2026-08-15.md` §K8. Started 2026-08-16, after K7.

## What "hardening" is protecting against

An **unattended tablet in a public room, facing the street.** The threat is not a determined attacker
with tools; it is a bored customer, a child, and a member of staff who wanted to check something.
Every escape ends the same way: the next customer walks up to a home screen instead of a menu, and
the restaurant does not find out until someone complains.

## Split: what travels with the code, what is device configuration

Only the first half can be tested in CI. The second half is a checklist a human performs on the
device once, and it is written down here because an undocumented setup step is one that gets skipped
on the second tablet.

### In the code — done, and tested

- **`PopScope(canPop: false)` on both tablet surfaces.** At the root route an unhandled Android back
  gesture **backgrounds the app**. On an unattended kiosk that hands the next person a tablet. The
  kiosk now consumes the back and treats it as activity (so a back press does not also idle the
  customer out mid-order); the KDS consumes it outright.
- **No router, one route.** The kiosk has no `go_router`, no named routes and no navigation stack —
  a test asserts `Navigator.canPop()` is false. A kiosk with a stack is a kiosk somebody can walk
  backwards out of.
- **No route to any admin surface.** The kiosk and KDS entrypoints import neither the customer app's
  router nor its auth graph. They initialise **no Supabase session at all**, so there is no signed-in
  identity on the device to escalate from.
- **Immersive sticky mode** (`SystemUiMode.immersiveSticky`) suppresses the status and navigation
  bars, so the notification shade is not one swipe away. Note this is a *deterrent*, not a lock:
  immersive sticky lets a determined swipe reveal the bars temporarily. **Screen pinning is the
  actual control.**
- **Landscape locked**, so a rotation cannot reflow a customer mid-order.

### On the device — a checklist, not code

**Android (the kiosk and the KDS both):**

1. **Device owner** via `adb shell dpm set-device-owner` on a freshly factory-reset tablet with no
   accounts added. Device owner **cannot** be set once a Google account exists — that is the step
   people discover after they have already signed in and have to factory-reset again.
2. **Screen pinning / lock task mode**, granted to the app by the device owner so it pins itself
   without the "hold back and overview to exit" escape a user-initiated pin leaves.
3. **Keep the screen on.** Needs `FLAG_KEEP_SCREEN_ON` (or `wakelock_plus`). ⚠ Deliberately **not**
   added yet: it is a native plugin, and adding it to the customer app's pubspec for a tablet-only
   feature is the same wrong trade as `sqlite3_flutter_libs`. It belongs with the app-package split,
   which is blocked on the parallel session's `lib/core/theme/*` edits.
4. **Auto-restart on crash** — device-owner policy plus a `HOME` intent filter, so a crash lands back
   in the kiosk rather than on the launcher.
5. Disable the status bar, safe mode, and factory reset via device-owner restrictions.

**iOS (the "bocav" iPhone / any iPad):**

- **Guided Access** (Settings → Accessibility) is the supported control without an MDM: it pins one
  app and disables the home gesture behind a passcode. It must be enabled per device, per boot.
- **Autonomous Single App Mode** is the real equivalent of Android's lock task, but it requires the
  device to be **supervised** through Apple Configurator or an MDM. Recorded as a known cost rather
  than assumed: a supervised device means a wipe-and-enroll of the tablet.

> **RESULT — K8 code half DONE 2026-08-16.** `PopScope` on the kiosk shell and the KDS board, plus
> three tests: back is **consumed** rather than passed to the platform, back does not idle a customer
> out mid-order, and the kiosk has no navigable stack. App suite **420/420**, analyze clean.
>
> **Not done, and both need the device:** the Android device-owner/screen-pinning setup and the iOS
> Guided Access pass are documented above but not performed, and the plan's proof — *ten minutes of
> adversarial poking: swipes, long-presses, volume+power, force-crash* — is exactly the kind of thing
> that cannot be faked in a widget test. Hardware-blocked while the parallel session holds the
> Samsung. `wakelock_plus` is deliberately deferred to the app-package split rather than added to the
> customer app's pubspec.
