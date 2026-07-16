#!/usr/bin/env bash
# Download one or more folders from Google Drive into outputs/ using rclone.
# Counterpart to upload_outputs.sh - see that script for the one-time
# `rclone config` setup instructions (same "gdrive" remote is reused here).
#
# Usage:
#   ./download_outputs.sh <folder_name|--all> [drive_source_path] [remote_name] [--dry-run]
#
# Examples:
#   ./download_outputs.sh home_dishes                              # <- gdrive:OpenReal2Sim_outputs/home_dishes
#   ./download_outputs.sh home_dishes experiments/2026-07-16        # <- gdrive:experiments/2026-07-16/home_dishes
#   ./download_outputs.sh --all backups/openreal2sim                # downloads every folder under that Drive path
#   ./download_outputs.sh home_dishes experiments/2026-07-16 gdrive --dry-run
#
# Note: existing local files are left alone unless the remote copy is newer
# (--update), and nothing local is ever deleted (this uses `rclone copy`,
# not `rclone sync`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUTS_DIR="$REPO_ROOT/outputs"
LOG_FILE="$REPO_ROOT/gdrive_download.log"

DEFAULT_REMOTE="gdrive"
DEFAULT_SRC="OpenReal2Sim_outputs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  error "Usage: $0 <folder_name|--all> [drive_source_path] [remote_name] [--dry-run]"
  exit 1
}

# Pull --dry-run out of the args wherever it appears, keep the rest positional.
ARGS=()
DRY_RUN=""
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ]; then
    DRY_RUN="--dry-run"
  else
    ARGS+=("$arg")
  fi
done
[ "${#ARGS[@]}" -ge 1 ] || usage
[ -n "$DRY_RUN" ] && warn "DRY RUN MODE - No files will be downloaded"

TARGET="${ARGS[0]}"
SRC_PATH="${ARGS[1]:-$DEFAULT_SRC}"
REMOTE="${ARGS[2]:-$DEFAULT_REMOTE}"
SRC_PATH="${SRC_PATH%/}"

if ! command -v rclone >/dev/null 2>&1; then
  error "rclone is not installed"
  echo "Install with: sudo apt install rclone"
  echo "Or: curl https://rclone.org/install.sh | sudo bash"
  exit 1
fi

if ! rclone listremotes | grep -q "^${REMOTE}:$"; then
  error "rclone remote '${REMOTE}' is not configured"
  echo ""
  echo "See upload_outputs.sh for setup instructions (run: rclone config)"
  exit 1
fi

# Resolve the folder(s) to download.
FOLDERS=()
if [ "$TARGET" = "--all" ]; then
  while IFS= read -r folder_name; do
    FOLDERS+=("$folder_name")
  done < <(rclone lsf "${REMOTE}:${SRC_PATH}" --dirs-only 2>/dev/null | sed 's#/$##')
  [ "${#FOLDERS[@]}" -gt 0 ] || { error "No folders found at ${REMOTE}:${SRC_PATH}"; exit 1; }
else
  if ! rclone lsd "${REMOTE}:${SRC_PATH}" 2>/dev/null | awk '{print $NF}' | grep -qx "$TARGET"; then
    error "'${REMOTE}:${SRC_PATH}/${TARGET}' does not exist on Drive."
    exit 1
  fi
  FOLDERS+=("$TARGET")
fi

info "Downloading from Google Drive"
info "Remote: ${REMOTE}:"
info "Source: ${SRC_PATH}/"
info "Folders: ${FOLDERS[*]}"
echo ""

for folder in "${FOLDERS[@]}"; do
  info "  - ${folder}: $(rclone size "${REMOTE}:${SRC_PATH}/${folder}" 2>/dev/null | tr '\n' ' ')"
done
echo ""

if [ -z "$DRY_RUN" ]; then
  read -p "Continue with download into '$OUTPUTS_DIR'? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Download cancelled"
    exit 0
  fi
fi

DOWNLOAD_OPTIONS=(
  --progress
  --stats 1s
  --update
  --transfers 8
  --checkers 8
  --log-file="$LOG_FILE"
  --log-level INFO
)

download_folder() {
  local folder="$1"
  local src="${REMOTE}:${SRC_PATH}/${folder}"
  local dst="$OUTPUTS_DIR/$folder"

  info "Downloading '$src' -> '$dst' ..."
  mkdir -p "$dst"
  rclone copy "$src" "$dst" "${DOWNLOAD_OPTIONS[@]}" $DRY_RUN
  info "  [OK] $folder"

  if [ -z "$DRY_RUN" ]; then
    echo ""
    info "Local contents of '$dst':"
    find "$dst" -type f | head -20
    local local_count
    local_count=$(find "$dst" -type f | wc -l)
    [ "$local_count" -gt 20 ] && echo "... (showing first 20 files)"
    info "Disk usage locally: $(du -sh "$dst" | cut -f1)"
  fi
  echo ""
}

for folder in "${FOLDERS[@]}"; do
  download_folder "$folder"
done

if [ -n "$DRY_RUN" ]; then
  info "Dry run complete. Re-run without --dry-run to actually download."
else
  info "All downloads complete!"
  info "Log file: $LOG_FILE"
fi
