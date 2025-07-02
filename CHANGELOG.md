# CHANGELOG

## [3.0] - June 2025

### Highlights

- **100% configuration via environment variables** (no need to edit the script):
  - `DELETE_SOURCE`: delete source file after successful conversion (`true`/`false`, default: `true`)
  - `MAX_JOBS`: number of parallel conversions (default: 2)
  - `INPUT_DIR`: input folder (default: `/input`)
  - `OUTPUT_DIR`: output folder (default: `/output`)
  - `LOOP_WAIT_SECONDS`: scan interval (default: 30)
- **Dynamic job pool management**: a new job starts as soon as a slot is free, no need to wait for all jobs to finish.
- **Source file and parent directory are deleted only on successful conversion.**
- **Bit depth preservation** (8, 10, or 12 bits) if supported by hardware.
- **Explicitly ignores `.log` files** during processing.
- **Detailed logging**:
  - `/tmp/erreurs_conversion.log`: global errors
  - `error.log` in each output folder: per-file errors
- **Designed for Docker**: everything is configured via environment variables, no script modification required.

---

## [2.3] - June 2025

- Previous version (dev branch): configuration mainly by editing the script, less dynamic job pool, less robust deletion, etc.
