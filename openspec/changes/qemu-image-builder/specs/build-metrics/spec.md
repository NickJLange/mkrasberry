## ADDED Requirements

### Requirement: Per-phase timing capture

The system SHALL measure wall-clock duration for each top-level pipeline phase (at minimum: fetch, configure, boot, ansible-apply, export, upload) and SHALL retain those measurements for emission at the end of the build.

#### Scenario: Each phase contributes a measured duration

- **WHEN** a build runs through all pipeline phases
- **THEN** the build retains a wall-clock duration for each phase that ran, with no phases missing from the recorded set

### Requirement: End-of-build emission

The system SHALL emit the captured per-phase timings to the build's output stream after the final phase completes, on both successful and failed builds. Phases that did not run (because an earlier phase failed) SHALL be reported as not-run rather than omitted.

#### Scenario: Successful build emits timings before exit

- **WHEN** a build completes successfully
- **THEN** the per-phase timings are written to the build's output before the process exits

#### Scenario: Failed build still emits timings

- **WHEN** a build fails in the ansible-apply phase
- **THEN** the per-phase timings emitted at exit include durations for the phases that ran (fetch, configure, boot, ansible-apply) and mark subsequent phases (export, upload) as not-run

### Requirement: Machine-readable timing output

The system SHALL support a machine-readable form of the timing output (in addition to any human-readable form) so an external consumer can ingest the timings without parsing free text.

#### Scenario: Machine-readable timings can be consumed downstream

- **WHEN** a build is invoked with the machine-readable timing output enabled
- **THEN** the build emits the per-phase timings in a structured format that a downstream tool can parse without regex over human-formatted text
