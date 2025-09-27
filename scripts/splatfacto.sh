#!/bin/bash

set -e

VIDEO_FILE="$1"
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: Video file not found: $VIDEO_FILE"
    exit 1
fi

VIDEO_DIR=$(dirname "$VIDEO_FILE")
VIDEO_BASENAME=$(basename "$VIDEO_FILE")

PIX_FMT=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
BITS_PER_SAMPLE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")

NEED_CONVERT=0
if [[ "$BITS_PER_SAMPLE" =~ ^[0-9]+$ ]] && [ "$BITS_PER_SAMPLE" -gt 8 ]; then
    NEED_CONVERT=1
elif [[ "$PIX_FMT" == *10* || "$PIX_FMT" == *12* || "$PIX_FMT" == *14* || "$PIX_FMT" == *16* || "$PIX_FMT" == *f32* || "$PIX_FMT" == *f64* ]]; then
    NEED_CONVERT=1
fi

VIDEO_FOR_PROCESS="$VIDEO_FILE"

if [ "$NEED_CONVERT" -eq 1 ]; then
    VIDEO_STEM=${VIDEO_BASENAME%.*}
    VIDEO_8BIT="${VIDEO_DIR}/${VIDEO_STEM}_8bit.mp4"

    if [ ! -f "$VIDEO_8BIT" ]; then
        echo "Detected high bit-depth input ($PIX_FMT, ${BITS_PER_SAMPLE:-unknown} bits). Converting to 8bit: $VIDEO_8BIT"
        ffmpeg -y -i "$VIDEO_FILE" -pix_fmt yuv420p "$VIDEO_8BIT"
    else
        echo "Using existing 8bit video: $VIDEO_8BIT"
    fi

    VIDEO_FOR_PROCESS="$VIDEO_8BIT"
else
    echo "Input appears to be 8bit already (pix_fmt: ${PIX_FMT:-unknown}). Conversion skipped."
fi

DATA_DIR="data/${VIDEO_BASENAME}"
OUTPUT_DIR="outputs/${VIDEO_BASENAME}"
EXPORT_DIR="exports/${VIDEO_BASENAME}"

uv run ns-process-data video \
    --data "$VIDEO_FOR_PROCESS" \
    --output-dir "$DATA_DIR"

uv run ns-train "splatfacto" \
    --data "$DATA_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --max-num-iterations 30000 \
    --vis viewer

CONFIG_FILE=$(find "$OUTPUT_DIR" -path "*/config.yml" | head -1)

uv run ns-export gaussian-splat --load-config "$CONFIG_FILE" --output-dir "$EXPORT_DIR"
echo "Exported: ${EXPORT_DIR}/splat.ply"
