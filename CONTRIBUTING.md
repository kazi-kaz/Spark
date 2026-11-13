<p align="center">
  <img src="docs/assets/spark-banner.svg" alt="Spark" width="60%">
</p>

# Contributing to Spark

Thanks for helping. This is the shared policy for code, reviews, documentation
and releases in this repository. It applies to human and automated
contributions alike. Component instructions add local build and style rules, and
third-party licenses and contribution restrictions still apply; this policy does
not replace them.

## Before you start

- **Read the notices for each directory you touch.** Third-party directories
  keep their own rules. Some require sign-off; `testrepos/Madeira/FEX/` does not
  accept AI-generated code, so fix FEX-adjacent problems in Wine, the
  `ntdll-unix` build or the app instead. Do not reformat upstream forks to match
  Spark.
- **Internal names stay `iridium`.** Folders, Swift type names, settings keys,
  the bundle identifier, `iridium.cfg`, log file names and CI scripts keep their
  names, because renaming them would reset settings, orphan game data or break
  the build. Only text the player sees says Spark.
- **Builds are manual and slow.** Each IPA build takes about 45 minutes, so
  batch related work into one change instead of many small ones.

## Change process

1. Describe the problem, intended behavior and affected component before editing.
2. Inspect callers, existing helpers, tests and working-tree changes. Preserve
   unrelated edits. Fix the shared cause rather than only the reported symptom.
3. Use a short-lived branch and one focused pull request. Keep refactors separate
   from behavior changes unless the refactor is required to fix the problem.
4. Test the changed behavior, document evidence and limits, and use the PR
   template.
5. Resolve review comments and checks before merging. Prefer squash merges with
   a clear imperative title. Personal names are not required in commit messages;
   use a GitHub noreply address if you like. Do not invent contributor
   identities.

Use titles such as `Fix controller reconnect handling`, not `Updates`. A strict
commit-prefix taxonomy is not required. Explain decisions in the PR rather than
writing a history of abandoned attempts. For changes to runtime architecture,
save formats, dependency licensing or trust boundaries, explain the choice,
migration and rollback in the PR when they apply.

Do not promise that a Spark change will be accepted by Iridium or Madeira. Read
their contribution rules before proposing anything upstream.

## Designing for Spark

Spark's screens follow one look: dark grounds, rounded cards, capsule buttons and
a single amber accent. The shared pieces live in
`iridium/apps/ios/Iridium/Views/SparkTheme.swift` and `SparkComponents.swift`;
use them instead of styling a screen from scratch.

| Token | Value | Use |
| --- | --- | --- |
| `SparkTheme.accent` | `#FFB627` amber | The main action on a screen, the selected tab, the bolt |
| `SparkTheme.problem` | `#FF9A85` coral | Failures and destructive actions |
| `SparkTheme.good` | `#8FE3C0` mint | A run or step that completed |
| `SparkTheme.ground` | `#08090C` | Page background |
| `SparkTheme.surface` | `#14161B` | Cards |
| `SparkTheme.raised` | `#1C1F26` | Secondary buttons and controls |
| `SparkTheme.onAccent` | `#17120D` | Text on amber |

- **Components:** `SparkCard` groups rows under a heading, `SparkRow` is an icon
  row with an optional value and chevron, `SparkPillButtonStyle` makes capsule
  buttons (`prominent: true` for amber), `SparkGameArt` shows artwork or a tinted
  initials tile, and `SparkStatusChip` shows a game's last run.
- **Amber means "do this", never "something is wrong".** Errors use coral.
  Keep one amber action per screen where you can.
- **Say what is known.** A game that closed normally is "Last run OK", not
  "Works". Launch diagnoses are labelled as likely causes. Do not show progress
  the runtime has not reported.
- **Accessibility is part of the design.** Check safe areas, Dynamic Type,
  VoiceOver labels, contrast (4.5:1 for text), Reduce Motion and both
  orientations. Touch targets are at least 44 points. Every action must be
  reachable with touch, keyboard and controller where that input is supported;
  use `controllerMenuScope()` with `MenuButton`, `MenuNavigationLink` and
  `menuFocusable` so the controller can reach it. Check focus, back/escape,
  modal dismissal and repeated menu opening for real.
- The design reference is the Spark UI mockups canvas (library, game page,
  launching, stopped, settings, in-game panel, splash and icon).

## Implementation

- Reuse existing code, standard libraries and native platform controls first.
  Add a dependency only with a reason, source revision, license review and owner.
- Keep UI, library state, runtime adapters and platform integration separate.
  UI reads shared launch state; it must not maintain a competing readiness state.
- Follow surrounding Swift, C, C++, Python and shell style. Use existing
  formatter settings. Do not add a global formatter over vendor code.
- Keep UI work on the UI thread. Keep blocking I/O and runtime operations off it.
  Give operations cancellation, bounded waits and useful failures. Shutdown must
  return control to the UI even if runtime cleanup fails.
- Validate imported paths, archive members, executable inputs and network data.
  Never interpolate untrusted input into shell commands. Do not swallow failures
  or claim success before the operation completes.
- Save and prefix changes need compatibility checks and recovery. Never erase
  user data as a default repair. Removing a library entry does not delete files.
- New settings keys use a `Spark` prefix, for example `SparkGameStatus.<id>`.
- Keep logs useful: phase, outcome, duration and a stable error code where
  useful. Redact paths, identifiers, tokens and pairing data before export. Do
  not log secrets, fabricate progress or treat a player screen as proof of
  rendering.

### Checks that read the source

Several checks inspect Swift source directly, so a UI change can fail CI without
any compile error:

- Tests in `ci/*.py` and `iridium/apps/ios/MadeiraSupportTests/*.py` assert exact
  wording and code snippets, for example the launch screen's buttons and the
  in-game menu's Cancel Launch. Search them for a string before you change it,
  and update the assertion in the same change when the design changes.
- Some harnesses compile a fixed list of files on their own (`ci/check-steam-ui.py`
  compiles `LibraryChrome.swift`, `SteamLibraryView.swift`,
  `RuntimeLogCapture.swift` and others). Those files cannot use `SparkTheme` or
  other new types, so they write Spark colors as literals.
- `iridium/Package.swift` lists app sources explicitly. A new Foundation-only
  file in `Iridium/` must be added there.

## Validation and evidence

Run the source checks for every change:

```sh
python3 check-public-source.py
python3 ci/check-standards.py
python3 -B -m unittest discover -s ci -p 'test_*.py'
git diff --check
```

Add a small regression test for changed nontrivial logic. Use the component's
existing tests; do not create a parallel framework. Reversible copy-only changes
need review, not a test that repeats their text. Changes to tests or checks must
not quietly weaken the rule they enforce.

Report these evidence levels separately:

| Evidence | What it establishes |
| --- | --- |
| Static/source checks | The checked source properties only |
| Build and package checks | Compilation, layout and signature state |
| Simulator interaction | The tested UI behavior in that simulator |
| Physical-device run | Only the tested device, OS, game and input paths |

Runtime verification records must name the source commit, build, device model,
OS, game and version, input method, steps, observed result and limits. Do not
publish serial numbers, UDIDs, private paths, game data or raw personal logs.
Verify frames, interaction, audio, save persistence and shutdown separately.
Mark untested items as untested. A passed build never means universal
compatibility.

### Building an IPA

Open **Actions → Build sideloading IPA → Run workflow**, choose the branch and
paste the full 40-character commit SHA; the workflow refuses a mismatch. The IPA
appears under the run's Artifacts. [docs/actions-ipa.md](docs/actions-ipa.md)
explains each job, and [docs/local-ipa-build.md](docs/local-ipa-build.md) covers
building on a Mac.

## Dependencies, privacy and security

Pin source revisions or digests, preserve upstream notices and record changes in
`CHANGES-FROM-UPSTREAM.md`. Update source collection with every linked dependency
change. Review the actual license expression and transitive inputs; a root
license or source URL alone is insufficient. Never bypass release audit blockers
by uploading local binaries. Do not claim formal compliance or certification
from a checklist.

Never commit or upload maintainer certificates, keys, profiles, pairing records,
private device logs, game files, commercial artwork or Apple SDKs. No signing
credentials belong in Actions secrets. Review filenames, metadata, logs and
archives, not only source strings. Rotate an exposed secret; deleting it from
the latest commit is not enough.

Spark does not bypass DRM. Steam-protected games start through Valve's own
client components with the player's account.

For security reports, use GitHub private vulnerability reporting if enabled. If
it is unavailable, open a minimal issue asking for a private reporting channel
without exploit details or personal data. No response-time guarantee is offered.
Do not test systems or accounts without permission.

## CI and repository controls

Source checks may run on pushes and pull requests. Compilation and release work
must be manual (`workflow_dispatch`). Do not add tag, push, schedule or PR build
triggers. Pin third-party Actions to full commits. Use read-only permissions by
default; never run untrusted PR code with secrets or `pull_request_target`.

The maintainer should protect `main` against deletion and force pushes, and
require pull requests, resolved conversations and the `privacy` source-check
job. Require an independent approval when another maintainer is available. Do
not configure an impossible self-approval rule for a sole maintainer. Any
emergency bypass must be documented and followed by review. GitHub settings
enforce these protections; this document alone does not enable them.

## Releases

Follow [the release policy](docs/releasing.md) and its fixed description
template. No build, tag, draft release or publication happens merely because a
PR merges. The maintainer chooses each run.
