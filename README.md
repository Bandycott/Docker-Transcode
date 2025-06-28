<p align="center">
  <img src="https://img.icons8.com/?size=100&id=32418&format=png&color=000000" class="logo" width="120"/>
</p>

# docker-transcode

**Automated video transcoding to H.265 (HEVC) using Intel QuickSync hardware acceleration, designed for Docker environments.**

## Features

- **Automatic conversion** of all videos from `/input` to `/output` using H.265 (HEVC).
- **MKV files** are converted to H.265 MKV, preserving all audio, subtitles, and chapters.
- **Other formats** are converted to H.265 MP4, preserving audio tracks.
- **Bit depth preservation** (8, 10, or 12 bits) when supported by hardware.
- **Source deletion** only after successful conversion.
- **Removes empty directories** in `/input` after processing.
- **Maintains original folder structure** in `/output`.
- **Progress display** in 10% increments during conversion.
- **Detailed logging**:
  - Global errors in `/tmp/erreurs_conversion.log`
  - Per-file errors in `error.log` within the output directory.
- **Parallel processing**: configurable pool (default: 2 concurrent jobs).
- **Ignores `.log` files** in processing.
- **Runs continuously**: watches `/input` for new files.

## Requirements

- **Docker** (tested with [linuxserver/ffmpeg](https://hub.docker.com/r/linuxserver/ffmpeg))
- **Intel® CPU with QuickSync** (tested on Intel® Core™ i5-14500)
- **/dev/dri** mapped into the container for hardware acceleration

## Usage

### 1. Prepare Folders

Create two folders on your host:

```bash
mkdir -p /path/to/input /path/to/output
```

### 2. Run the Container

```bash
docker run -d \
  --name=transcode \
  --device /dev/dri:/dev/dri \
  -v /path/to/input:/input \
  -v /path/to/output:/output \
  -v /etc/localtime:/etc/localtime:ro \
  linuxserver/ffmpeg \
  bash /config/convert.sh
```

- Replace `/path/to/input` and `/path/to/output` with your actual directories.
- Place `convert.sh` in the `/config` folder or adjust the path as needed.

### 3. Add Files

Drop your video files (MKV, MP4, etc.) into `/input`.
Converted files will appear in `/output` with the same folder structure.

## Script Details

- **Dependencies** are installed automatically on first run (vainfo, intel-media-va-driver-non-free, etc.).
- **Bit depth** is detected and preserved if supported by your CPU/GPU.
- **Progress** is printed to the console every 10% of conversion.
- **Logs**:
  - `/tmp/erreurs_conversion.log`: all global errors.
  - `error.log` in each output folder: detailed per-file errors.

## Configuration

You can adjust the number of concurrent jobs by editing the script variable:

```bash
MAX_JOBS=2
```

## Example

```
/input/Movies/Film1.mkv   -->   /output/Movies/Film1.mkv
/input/Series/Episode1.mp4 -->   /output/Series/Episode1.mp4
```

## Hardware Acceleration

- Uses **Intel QuickSync (QSV)** for fast and efficient H.265 encoding.
- Make sure `/dev/dri` is available and your CPU supports QSV (i5-14500: OK).

## Troubleshooting

- Check `/tmp/erreurs_conversion.log` for global errors.
- Check `error.log` in the output folder for file-specific issues.
- Ensure your Docker image and host have the necessary VAAPI/QSV drivers.

## Author

- **Bandycott**
- Script version: 2.3 (June 2025)

## License

A venir

[^1]: convert.sh
