# CHANGELOG

## [3.2] - 2025-08-11

### Highlights

- **Discord notifications**: Added via Webhook for job start, success, failure, and global processing end.
- **Advanced file status management**: Unique end notification and handling of empty output files.
- **Job pool refactoring**: Increased robustness with PID table and removal of finished jobs.
- **File stability checks**: Ensures files are stable and not opened by another process before processing.
- **Find command syntax correction**: Escaped parentheses in find commands.
- **Global end notification**: Sent every time the input folder becomes empty again.

---

## [3.1] - July 2025

### Highlights

- **Extension filtering**: Only compatible multimedia files are processed (explicit list of extensions).
- **Improved script header**: More detailed description, author, and versioning.
- **Robust file handling**: `.log` files are ignored with an extra security check.
- **Automatic dependency installation**: ffmpeg, vainfo, QSV drivers, etc. installed at first run.
- **Enhanced documentation**: Comments and usage instructions improved for Docker environments.
- **No breaking changes**: All previous 3.0 features are preserved.

---

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
