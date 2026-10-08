# TypeScript 7 oracle capture

This is an evidence capture tool, not a semantic implementation or a benchmark. Pin exact TS7 7.0.2 and run three tiny projects to obtain complete raw stdout/stderr, exit statuses, command-line flags, version text, and input SHA-256s.

The initially committed cases cover:
- a clean result;
- TypeScript type and property diagnostics;
- a diagnostic after a supplementary Unicode character, plus CRLF lines.

CI produces a short-lived `ts7-oracle-raw` artifact. Once reviewed, selected records may become immutable goldens in a separate change with a documented normalization policy. Do not commit guessed diagnostics or declare C1 compatibility from these captures.

The capture program enforces that intentionally failing cases actually produce non-empty diagnostics, and that the clean case exits 0. It does not yet compare tsodin against TS7, because tsodin's checker does not yet exist.

Local invocation after installing the pinned compiler:

    TSODIN_TSC=/path/to/tsc TSODIN_ORACLE_OUTPUT=/tmp/oracle-capture node tools/oracle/capture.mjs
