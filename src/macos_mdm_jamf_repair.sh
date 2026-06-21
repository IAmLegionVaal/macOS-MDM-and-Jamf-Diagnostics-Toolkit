#!/bin/bash
set -u

DO_REPAIR=false
RENEW_ENROLLMENT=false
JAMF_RECON=false
JAMF_MANAGE=false
JAMF_EVENT=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: macos_mdm_jamf_repair.sh [options]

  --repair                 Restart MDM, profile and managed-client services.
  --renew-enrollment       Run Apple's interactive MDM enrolment renewal.
  --jamf-recon             Submit Jamf inventory.
  --jamf-manage            Reapply Jamf management framework settings.
  --jamf-policy EVENT      Run one Jamf custom policy event.
  --dry-run                Show actions without changing the Mac.
  --yes                    Skip confirmation prompts.
  --output DIR             Save logs and verification output in DIR.
  -h, --help               Show help.

The tool does not unenrol the Mac, remove profiles, delete the Jamf framework,
or expose management credentials.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair) DO_REPAIR=true; shift ;;
    --renew-enrollment) RENEW_ENROLLMENT=true; DO_REPAIR=true; shift ;;
    --jamf-recon) JAMF_RECON=true; DO_REPAIR=true; shift ;;
    --jamf-manage) JAMF_MANAGE=true; DO_REPAIR=true; shift ;;
    --jamf-policy) JAMF_EVENT="${2:-}"; DO_REPAIR=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
$DO_REPAIR || { echo "Choose at least one repair action." >&2; exit 2; }
if [ -n "$JAMF_EVENT" ]; then
  case "$JAMF_EVENT" in *[!A-Za-z0-9._-]*|'') echo "Jamf event contains unsupported characters." >&2; exit 2 ;; esac
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./mdm-jamf-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_admin() {
  description="$1"; shift
  if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" /usr/bin/sudo "$@"; fi
}
find_jamf() {
  for path in /usr/local/bin/jamf /usr/sbin/jamf; do [ -x "$path" ] && { echo "$path"; return 0; }; done
  return 1
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "MDM enrolment:"
    /usr/bin/profiles status -type enrollment 2>&1 || true
    echo
    echo "Bootstrap token:"
    /usr/bin/profiles status -type bootstraptoken 2>&1 || true
    echo
    echo "Management processes:"
    ps -Ao pid,user,etime,comm,args | grep -Ei 'mdmclient|profilesd|ManagedClient|jamf|JamfDaemon' | grep -v grep || true
    echo
    echo "Jamf status:"
    JAMF=$(find_jamf || true)
    if [ -n "$JAMF" ]; then "$JAMF" version 2>&1 || true; "$JAMF" checkJSSConnection 2>&1 || true; else echo "Jamf binary not installed"; fi
  } > "$VERIFY" 2>&1
}

verify
if ! confirm "Apply the selected MDM and Jamf repair actions?"; then log "Repair cancelled."; exit 10; fi

for service in com.apple.mdmclient.daemon com.apple.ManagedClient.enroll com.apple.ManagedClient; do
  run_admin "Restarting launch service $service" /bin/launchctl kickstart -k "system/$service" || true
done
for process_name in mdmclient profilesd ManagedClient; do
  if pgrep -x "$process_name" >/dev/null 2>&1; then run_admin "Restarting $process_name" /usr/bin/killall "$process_name" || true; fi
done

if $RENEW_ENROLLMENT && confirm "Start Apple's MDM enrolment renewal? User interaction may be required."; then
  run_admin "Starting MDM enrolment renewal" /usr/bin/profiles renew -type enrollment || true
fi

JAMF=$(find_jamf || true)
if $JAMF_RECON || $JAMF_MANAGE || [ -n "$JAMF_EVENT" ]; then
  if [ -z "$JAMF" ]; then
    FAILURES=$((FAILURES + 1)); log "WARNING: Jamf binary is not installed."
  else
    $JAMF_MANAGE && run_admin "Reapplying Jamf management settings" "$JAMF" manage || true
    $JAMF_RECON && run_admin "Submitting Jamf inventory" "$JAMF" recon || true
    if [ -n "$JAMF_EVENT" ]; then run_admin "Running Jamf policy event $JAMF_EVENT" "$JAMF" policy -event "$JAMF_EVENT" || true; fi
  fi
fi

if ! $DRY_RUN; then sleep 6; fi
verify
if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
