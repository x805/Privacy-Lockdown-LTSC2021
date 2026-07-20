![Version](https://img.shields.io/badge/Version-1.6.1-success.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%20IoT%20Enterprise%20LTSC%202021-lightgrey.svg)

## v1.6.1

Minor release. One behavior change, one documentation improvement — not bug fixes in the strict sense, since v1.6.0's `WER_MODE=LOCAL` option worked correctly as designed.

### Changed
- **Windows Error Reporting is now permanently, unconditionally disabled.** The `WER_MODE` toggle (`OFF` / `LOCAL`) has been removed entirely. WER is always fully off: no local crash dumps, nothing sent to Microsoft, no user-facing crash prompt.

### Added
- A clarifying comment explaining that when this script is run via "Run as Administrator" using a different account than the one you're logged into, `HKCU` refers to the admin account's profile — the logged-in user's profile is still covered separately by the per-profile loop, but won't reflect changes until they log out and back in.

### Upgrading from 1.6.0

**Safe to run directly over an already-hardened v1.6.0 system — no rollback-first, no reboot-then-repair dance needed.** Every run is fully self-contained: its own timestamped folder, its own backup of whatever it finds in the registry at that moment, its own rollback script. It never depends on any previous run.

The one thing worth understanding: each run's backup captures a key's value *as found when that run starts*, not stock Windows defaults. So on a machine v1.6.0 already hardened, v1.6.1's backup captures the *1.6.0-hardened* state — meaning your original v1.6.0 run folder remains your only path back to true factory settings. Keep it.

In practice, almost every setting in 1.6.1 is identical to 1.6.0, so re-running is a no-op. The only place a real difference can occur is WER, and only if you'd manually switched to `WER_MODE=LOCAL` — in that case the old non-policy `LocalDumps` keys are left in place, orphaned but harmless, once the new permanent-off policy key takes precedence. See [CHANGELOG.md](CHANGELOG.md) for the full detail.

See [CHANGELOG.md](CHANGELOG.md) for the complete version history back to 1.0.0.
