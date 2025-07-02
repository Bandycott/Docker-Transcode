<p align="center">
  <img src="https://img.icons8.com/?size=100&id=32418&format=png&color=000000" class="logo" width="120"/>
</p>

# docker-transcode

**Automated video transcoding to H.265 (HEVC) using Intel QuickSync hardware acceleration, designed for Docker environments.**

## Features

- Automatic conversion of all videos from the input folder to the output folder in H.265 (HEVC)
- **MKV files** are converted to H.265 MKV, preserving all audio, subtitles, and chapters
- Other formats are converted to H.265 MP4, preserving audio tracks
- Maintains the original folder structure in the output directory
- Progress display in 10% increments in the console
- Configurable parallel processing
- Optional deletion of source files and empty folders after successful conversion
- Continuous monitoring of the input folder

## Requirements

- **Docker** (tested with [linuxserver/ffmpeg](https://hub.docker.com/r/linuxserver/ffmpeg))
- **Intel® CPU with QuickSync**
- **/dev/dri** mapped into the container for hardware acceleration

## Usage

### 1. Prepare folders

```bash
mkdir -p /path/to/input /path/to/output
```

### 2. Run the container

```bash
docker run -d \
  --name=transcode \
  --device /dev/dri:/dev/dri \
  -v /path/to/input:/input \
  -v /path/to/output:/output \
  -v /etc/localtime:/etc/localtime:ro \
  -e DELETE_SOURCE=true \
  -e MAX_JOBS=2 \
  -e LOOP_WAIT_SECONDS=30 \
  linuxserver/ffmpeg \
  bash /config/convert.sh
```

- Adjust the environment variables as needed.
- Place `convert.sh` in `/config` or adjust the path accordingly.

### 3. Add files

Drop your videos into `/input`. Converted files will appear in `/output` with the same folder structure.

## Script details

- **Dependencies** are installed automatically on first run (vainfo, intel-media-va-driver-non-free, etc.)
- **Bit depth** is detected and preserved if supported
- **Progress** is displayed every 10%
- **Logs**:
  - `/tmp/erreurs_conversion.log`: global errors
  - `error.log` in each output folder: detailed errors
- **Source file and parent folder** are deleted only after successful conversion
- **`.log` files** are ignored

## Example

```
/input/Films/Film1.mkv   -->   /output/Films/Film1.mkv
/input/Series/Episode1.mp4 -->   /output/Series/Episode1.mp4
```

## Hardware acceleration

- Uses **Intel QuickSync (QSV)** for fast and efficient H.265 encoding
- Make sure `/dev/dri` is available and your CPU supports QSV

## Troubleshooting

- Check `/tmp/erreurs_conversion.log` for global errors
- Check `error.log` in the output folder for per-file errors
- Ensure your Docker image and host have the necessary VAAPI/QSV drivers

## Author

- **Bandycott**
- Script version: 3.0 (June 2025)

## License

TBD

[^1]: convert.sh
