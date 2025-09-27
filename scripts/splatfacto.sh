#!/bin/bash

set -ex

VIDEO_FILE="$1"
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: Video file not found: $VIDEO_FILE"
    exit 1
fi

VIDEO_DIR=$(dirname "$VIDEO_FILE")
VIDEO_BASENAME=$(basename "$VIDEO_FILE")

PIX_FMT=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
BITS_PER_SAMPLE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
ROTATE_TAG=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
ROTATE_SIDE_DATA=$(ffprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" | sed -n 's/^rotation=//p' | head -1)

ROTATE_DEG=0
if [[ "$ROTATE_TAG" =~ ^-?[0-9]+$ ]]; then
    ROTATE_DEG=$ROTATE_TAG
elif [[ "$ROTATE_SIDE_DATA" =~ ^-?[0-9]+$ ]]; then
    ROTATE_DEG=$ROTATE_SIDE_DATA
fi

# When shooting video on an iPhone, the camera tilt may be stored in the metadata rather than in the video itself.
ROTATE_DEG=$(( (ROTATE_DEG % 360 + 360) % 360 ))
case $ROTATE_DEG in
    0) ROTATE_FILTER="" ;;
    90) ROTATE_FILTER="transpose=1" ;;
    180) ROTATE_FILTER="transpose=1,transpose=1" ;;
    270) ROTATE_FILTER="transpose=2" ;;
    *)
        echo "Warning: Unsupported rotation metadata detected (${ROTATE_DEG} deg). Skipping manual correction."
        ROTATE_FILTER=""
        ROTATE_DEG=0
        ;;
esac

NEED_CONVERT=0
if [[ "$BITS_PER_SAMPLE" =~ ^[0-9]+$ ]] && [ "$BITS_PER_SAMPLE" -gt 8 ]; then
    NEED_CONVERT=1
elif [[ "$PIX_FMT" == *10* || "$PIX_FMT" == *12* || "$PIX_FMT" == *14* || "$PIX_FMT" == *16* || "$PIX_FMT" == *f32* || "$PIX_FMT" == *f64* ]]; then
    NEED_CONVERT=1
fi

if [ $ROTATE_DEG -ne 0 ]; then
    NEED_CONVERT=1
fi

VIDEO_FOR_PROCESS="$VIDEO_FILE"

if [ "$NEED_CONVERT" -eq 1 ]; then
    VIDEO_STEM=${VIDEO_BASENAME%.*}
    VIDEO_PROCESSED="${VIDEO_DIR}/${VIDEO_STEM}_processed.mp4"

    if [ ! -f "$VIDEO_PROCESSED" ]; then
        echo "Preparing intermediary video: $VIDEO_PROCESSED"
        echo "  pix_fmt: ${PIX_FMT:-unknown}, bits: ${BITS_PER_SAMPLE:-unknown}, rotate: ${ROTATE_DEG}"
        FFMPEG_ARGS=(ffmpeg -y)
        if [ -n "$ROTATE_FILTER" ]; then
            FFMPEG_ARGS+=(-noautorotate)
        fi
        FFMPEG_ARGS+=(-i "$VIDEO_FILE")
        if [ -n "$ROTATE_FILTER" ]; then
            FFMPEG_ARGS+=(-vf "$ROTATE_FILTER")
        fi
        FFMPEG_ARGS+=(-pix_fmt yuv420p -c:a copy)
        if [ -n "$ROTATE_FILTER" ]; then
            FFMPEG_ARGS+=(-metadata:s:v:0 rotate=0)
        fi
        FFMPEG_ARGS+=("$VIDEO_PROCESSED")
        "${FFMPEG_ARGS[@]}"
    else
        echo "Using existing processed video: $VIDEO_PROCESSED"
    fi

    VIDEO_FOR_PROCESS="$VIDEO_PROCESSED"
else
    echo "Input appears to be 8bit already (pix_fmt: ${PIX_FMT:-unknown}). Conversion skipped."
fi

PEOCESSED_DIR="processed/${VIDEO_BASENAME}"
OUTPUT_DIR="outputs/${VIDEO_BASENAME}"
EXPORT_DIR="exports/${VIDEO_BASENAME}"

uv run ns-process-data video \
    --data "$VIDEO_FOR_PROCESS" \
    --output-dir "$PEOCESSED_DIR"

uv run ns-train "splatfacto" \
    --data "$PEOCESSED_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --max-num-iterations 30000 \
    --vis viewer

CONFIG_FILE=$(find "$OUTPUT_DIR" -path "*/config.yml" | head -1)

uv run ns-export gaussian-splat --load-config "$CONFIG_FILE" --output-dir "$EXPORT_DIR"
echo "Exported: ${EXPORT_DIR}/splat.ply"
