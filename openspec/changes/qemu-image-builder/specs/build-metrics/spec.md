## ADDED Requirements

### Requirement: Per-phase timing capture

The system SHALL measure wall-clock duration, using a monotonic clock, for each phase in the canonical pipeline phase list and SHALL retain those measurements for emission at the end of the build. The canonical phase list, in execution order, is: `fetch`, `prep`, `boot`, `apt-refresh`, `ansible-apply`, `export`, `compress`, `upload`. These names SHALL be used verbatim in emitted records.

#### Scenario: Each phase contributes a measured duration

- **WHEN** a build runs through all pipeline phases
- **THEN** the build retains a wall-clock duration for each of the eight canonical phases, with no phases missing from the recorded set

### Requirement: End-of-build emission

The system SHALL emit the captured per-phase timings after the final phase completes or the build fails, on both successful and failed builds, as a human-readable table on stderr and as the machine-readable output defined below. Every canonical phase SHALL appear exactly once with one of the statuses `ok`, `failed`, `not_run` (not attempted because an earlier phase failed), or `skipped` (intentionally disabled, such as `upload` under `--no-upload`). Phases SHALL NOT be omitted.

#### Scenario: Successful build emits timings before exit

- **WHEN** a build completes successfully
- **THEN** the per-phase timings are written before the process exits, with every executed phase `ok` and any intentionally disabled phase (such as `upload` under `--no-upload`) `skipped`

#### Scenario: Failed build still emits timings

- **WHEN** a build fails in the `ansible-apply` phase
- **THEN** the emitted timings include durations with status `ok` for `fetch`, `prep`, `boot`, and `apt-refresh`, a duration with status `failed` for `ansible-apply`, and records with status `not_run` for `export`, `compress`, and `upload`

#### Scenario: Skipped upload is reported

- **WHEN** a build is invoked with `--no-upload` and completes
- **THEN** the `upload` phase is reported with status `skipped`

### Requirement: Machine-readable timing output

The system SHALL always write machine-readable timings as a JSON Lines file (UTF-8, one JSON object per line). The path defaults to `build_images/<host>-<build-ts>.timings.jsonl` and is configurable with `--timing-output <path>`. The file SHALL contain one `phase` record per canonical phase in execution order, followed by exactly one `summary` record as the final line.

Every record SHALL include: `schema_version` (integer, currently `1`), `type` (`"phase"` or `"summary"`), `build_id` (`<host>-<build-ts>`), and `host`.

Each `phase` record SHALL additionally include:

- `phase` — a canonical phase name.
- `seq` — 1-based position in the canonical list.
- `status` — `ok`, `failed`, `not_run`, or `skipped`.
- `started_at` — RFC 3339 UTC timestamp, or `null` when the status is `not_run` or `skipped`.
- `duration_s` — elapsed seconds as a number, or `null` when the status is `not_run` or `skipped`.
- `error` — a short message string when the status is `failed`, otherwise `null`.

The `summary` record SHALL additionally include:

- `status` — `ok` or `failed`.
- `failed_phase` — a phase name, or `null`.
- `release_id` — a string, or `null` if not yet resolved.
- `total_duration_s` — a number.
- `exit_code` — an integer.

New fields MAY be added without changing `schema_version`; removing or renaming fields, or changing their meaning, SHALL increment it.

#### Scenario: Machine-readable timings can be consumed downstream

- **WHEN** a build finishes, successfully or not
- **THEN** the timings file contains eight `phase` records in canonical order followed by one `summary` record, each line parses as JSON, and durations are in seconds

#### Scenario: Not-run phases are explicit records

- **WHEN** a build fails in the `boot` phase
- **THEN** the timings file contains `phase` records for `apt-refresh` through `upload` with status `not_run` and `null` duration, and the `summary` record has `status: "failed"` and `failed_phase: "boot"`
