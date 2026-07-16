#!/usr/bin/env bash
# Upload one or more folders from outputs/ to Google Drive using rclone.
#
# One-time setup (run once per machine):
#   1. Install rclone:
#        sudo apt install rclone
#        (or: curl https://rclone.org/install.sh | sudo bash)
#   2. Configure a remote:
#        rclone config
#        - Choose "n" for new remote
#        - Name: gdrive   (must match REMOTE in DEFAULT_REMOTE below, or pass a
#                          different name as the 3rd script argument)
#        - Storage: choose "drive" (Google Drive) - the number may vary by rclone version
#        - client_id: leave blank
#        - client_secret: leave blank
#        - scope: choose 1 (full access)
#        - root_folder_id: leave blank
#        - service_account_file: leave blank
#        - Edit advanced config: n
#        - Use auto config: y if on a desktop with a browser; n if on a
#          headless server (it will print a command to run on a machine
#          with a browser, then paste the resulting token back here)
#        - Configure this as a Shared Drive (Team Drive): usually n
#   3. Test it: rclone lsd gdrive:
#      (should list the folders in your Google Drive without error)
#      Credentials are cached in ~/.config/rclone/rclone.conf - this setup
#      only needs to be done once per machine.
#
# Usage:
#   ./upload_outputs.sh <folder_name|--all> [drive_destination_path] [remote_name] [--dry-run]
#
# Examples:
#   ./upload_outputs.sh home_dishes                              # -> gdrive:OpenReal2Sim_outputs/home_dishes
#   ./upload_outputs.sh home_dishes experiments/2026-07-16        # -> gdrive:experiments/2026-07-16/home_dishes
#   ./upload_outputs.sh --all backups/openreal2sim                # uploads every folder under outputs/
#   ./upload_outputs.sh home_dishes experiments/2026-07-16 gdrive --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUTS_DIR="$REPO_ROOT/outputs"
LOG_FILE="$REPO_ROOT/gdrive_upload.log"

DEFAULT_REMOTE="gdrive"
DEFAULT_DEST="OpenReal2Sim_outputs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  error "Usage: $0 <folder_name|--all> [drive_destination_path] [remote_name] [--dry-run]"
  echo
  echo "Available folders in $OUTPUTS_DIR:"
  find "$OUTPUTS_DIR" -mindepth 1 -maxdepth 1 -printf '  - %f\n' 2>/dev/null || true
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
[ -n "$DRY_RUN" ] && warn "DRY RUN MODE - No files will be uploaded"

TARGET="${ARGS[0]}"
DEST_PATH="${ARGS[1]:-$DEFAULT_DEST}"
REMOTE="${ARGS[2]:-$DEFAULT_REMOTE}"
DEST_PATH="${DEST_PATH%/}"

if ! command -v rclone >/dev/null 2>&1; then
  error "rclone is not installed"
  echo "Install with: sudo apt install rclone"
  echo "Or: curl https://rclone.org/install.sh | sudo bash"
  exit 1
fi

if ! rclone listremotes | grep -q "^${REMOTE}:$"; then
  error "rclone remote '${REMOTE}' is not configured"
  echo ""
  echo "Quick setup:"
  echo "  1. rclone config"
  echo "  2. Choose 'n' for new remote"
  echo "  3. Name: ${REMOTE}"
  echo "  4. Storage: Google Drive"
  echo "  5. Follow the prompts (leave most blank, choose full access)"
  exit 1
fi

# Resolve the folder(s) to upload.
FOLDERS=()
if [ "$TARGET" = "--all" ]; then
  while IFS= read -r -d '' folder_path; do
    FOLDERS+=("$(basename "$folder_path")")
  done < <(find "$OUTPUTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
  [ "${#FOLDERS[@]}" -gt 0 ] || { error "No folders found in $OUTPUTS_DIR"; exit 1; }
else
  [ -d "$OUTPUTS_DIR/$TARGET" ] || { error "'$OUTPUTS_DIR/$TARGET' does not exist or is not a directory."; exit 1; }
  FOLDERS+=("$TARGET")
fi

info "Uploading to Google Drive"
info "Remote:      ${REMOTE}:"
info "Destination: ${DEST_PATH}/"
info "Folders:     ${FOLDERS[*]}"
echo ""

TOTAL_SIZE=$(du -shc "${FOLDERS[@]/#/$OUTPUTS_DIR/}" 2>/dev/null | tail -1 | cut -f1)
TOTAL_FILES=$(find "${FOLDERS[@]/#/$OUTPUTS_DIR/}" -type f | wc -l)
info "Total size:  $TOTAL_SIZE"
info "Total files: $TOTAL_FILES"
echo ""

if [ -z "$DRY_RUN" ]; then
  read -p "Continue with upload? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Upload cancelled"
    exit 0
  fi
fi

UPLOAD_OPTIONS=(
  --progress
  --stats 1s
  --update
  --transfers 8
  --checkers 8
  --log-file="$LOG_FILE"
  --log-level INFO
)

EXCLUDE_PATTERNS=(
  --exclude "*.tmp"
  --exclude "*.swp"
  --exclude ".git/"
  --exclude "__pycache__/"
  --exclude "*.pyc"
  --exclude ".DS_Store"
  --exclude "Thumbs.db"
)

upload_folder() {
  local folder="$1"
  local src="$OUTPUTS_DIR/$folder"
  local dst="${REMOTE}:${DEST_PATH}/${folder}"

  info "Uploading '$folder' -> '$dst' ..."
  rclone copy "$src" "$dst" "${UPLOAD_OPTIONS[@]}" "${EXCLUDE_PATTERNS[@]}" $DRY_RUN
  info "  [OK] $folder"

  if [ -z "$DRY_RUN" ]; then
    echo ""
    info "Remote contents of '$dst':"
    rclone lsl "$dst" 2>/dev/null | head -20
    local remote_count
    remote_count=$(rclone lsl "$dst" 2>/dev/null | wc -l)
    [ "$remote_count" -gt 20 ] && echo "... (showing first 20 files)"
    info "Disk usage on remote:"
    rclone size "$dst"
  fi
  echo ""
}

for folder in "${FOLDERS[@]}"; do
  upload_folder "$folder"
done

if [ -n "$DRY_RUN" ]; then
  info "Dry run complete. Re-run without --dry-run to actually upload."
else
  info "All uploads complete!"
  info "Log file: $LOG_FILE"
fi
