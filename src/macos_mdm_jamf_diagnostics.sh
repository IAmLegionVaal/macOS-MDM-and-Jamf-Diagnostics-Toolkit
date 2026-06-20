#!/bin/bash
set -u

OUTPUT_DIR=""
HOURS=24
TEST_CONNECTIVITY=false

usage() {
  echo "Usage: macos_mdm_jamf_diagnostics.sh [--hours N] [--test-connectivity] [--output DIR]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --test-connectivity) TEST_CONNECTIVITY=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$HOURS" in
  ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This toolkit must run on macOS." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./mdm-jamf-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/mdm-jamf-report.txt"
CSV="$OUTPUT_DIR/components.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"
echo 'component,path,present,version_or_state' > "$CSV"

section() {
  title="$1"
  shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

run_shell() {
  title="$1"
  command="$2"
  {
    printf '\n===== %s =====\n' "$title"
    /bin/bash -c "$command"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

record_component() {
  component="$1"
  path="$2"
  present="$3"
  state="$4"
  safe_component=$(printf '%s' "$component" | sed 's/"/""/g')
  safe_path=$(printf '%s' "$path" | sed 's/"/""/g')
  safe_state=$(printf '%s' "$state" | sed 's/"/""/g')
  printf '"%s","%s","%s","%s"\n' "$safe_component" "$safe_path" "$present" "$safe_state" >> "$CSV"
}

section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "MDM enrollment status" /usr/bin/profiles status -type enrollment
section "Bootstrap token status" /usr/bin/profiles status -type bootstraptoken
run_shell "Installed configuration profiles" '/usr/bin/profiles list -all 2>/dev/null || /usr/bin/profiles show -type configuration 2>/dev/null || true'
run_shell "Enrollment profile" '/usr/bin/profiles show -type enrollment 2>/dev/null || true'
run_shell "Management processes" 'ps -Ao pid,user,etime,comm,args | grep -Ei "mdmclient|profiles|ManagedClient|jamf" | grep -v grep || true'
run_shell "Management launch daemons" 'find /Library/LaunchDaemons /Library/LaunchAgents -maxdepth 1 -type f \( -iname "*jamf*" -o -iname "*mdm*" -o -iname "*managed*" \) -print -exec ls -l {} \; 2>/dev/null || true'
run_shell "Configuration profile database metadata" 'find /var/db/ConfigurationProfiles -maxdepth 3 -type f -printf "%p\n" 2>/dev/null || find /var/db/ConfigurationProfiles -maxdepth 3 -type f -print 2>/dev/null || true'
run_shell "Management certificate indicators" '/usr/bin/security find-certificate -a -Z /Library/Keychains/System.keychain 2>/dev/null | grep -Ei "SHA-256|labl|alis|MDM|APNS|Jamf|Device Management" | head -n 500 || true'

JAMF_BIN=""
for candidate in /usr/local/bin/jamf /usr/sbin/jamf "/Library/Application Support/JAMF/bin/jamf"; do
  if [ -x "$candidate" ]; then
    JAMF_BIN="$candidate"
    break
  fi
done

JAMF_PRESENT=false
JAMF_VERSION="not-installed"
JAMF_CONNECTIVITY="not-tested"

if [ -n "$JAMF_BIN" ]; then
  JAMF_PRESENT=true
  JAMF_VERSION="$($JAMF_BIN -version 2>>"$ERRORS" | tr '\n' ' ' | sed 's/"/\\"/g')"
  section "Jamf binary version" "$JAMF_BIN" -version
  run_shell "Jamf framework inventory" 'find "/Library/Application Support/JAMF" /usr/local/jamf /var/log -maxdepth 3 \( -iname "*jamf*" -o -iname "jamf.log" \) -print -exec ls -ld {} \; 2>/dev/null || true'
  run_shell "Recent Jamf log" 'tail -n 1000 /var/log/jamf.log 2>/dev/null || true'
  record_component "Jamf binary" "$JAMF_BIN" "true" "$JAMF_VERSION"

  if $TEST_CONNECTIVITY; then
    if "$JAMF_BIN" checkJSSConnection >> "$REPORT" 2>> "$ERRORS"; then
      JAMF_CONNECTIVITY="passed"
    else
      JAMF_CONNECTIVITY="failed"
    fi
  fi
else
  record_component "Jamf binary" "not-found" "false" "not-installed"
fi

for component in \
  "/usr/libexec/mdmclient" \
  "/System/Library/LaunchDaemons/com.apple.mdmclient.daemon.plist" \
  "/System/Library/LaunchAgents/com.apple.mdmclient.agent.plist" \
  "/var/db/ConfigurationProfiles"; do
  if [ -e "$component" ]; then
    record_component "macOS management component" "$component" "true" "present"
  else
    record_component "macOS management component" "$component" "false" "missing"
  fi
done

run_shell "Recent MDM and managed-client events" "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process == \"mdmclient\") OR (process == \"profiles\") OR (process == \"ManagedClient\") OR (eventMessage CONTAINS[c] \"MDM\") OR (eventMessage CONTAINS[c] \"configuration profile\")' 2>/dev/null | tail -n 3000"
run_shell "Recent Jamf unified-log events" "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process CONTAINS[c] \"jamf\") OR (eventMessage CONTAINS[c] \"jamf\")' 2>/dev/null | tail -n 3000"

ENROLLMENT_RAW="$(/usr/bin/profiles status -type enrollment 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')"
BOOTSTRAP_RAW="$(/usr/bin/profiles status -type bootstraptoken 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')"
MDM_ENROLLED=false
ADE_ENROLLED=false
BOOTSTRAP_ESCROWED=false

echo "$ENROLLMENT_RAW" | grep -Eqi 'MDM enrollment: Yes' && MDM_ENROLLED=true
echo "$ENROLLMENT_RAW" | grep -Eqi 'Enrolled via DEP: Yes' && ADE_ENROLLED=true
echo "$BOOTSTRAP_RAW" | grep -Eqi 'escrowed.*YES|escrowed to server: YES|Bootstrap Token escrowed' && BOOTSTRAP_ESCROWED=true

PROFILE_COUNT="$(/usr/bin/profiles list -all 2>/dev/null | grep -Ec 'attribute: name|profileIdentifier|Profile Identifier' || true)"
OVERALL="Healthy"
if ! $MDM_ENROLLED; then
  OVERALL="Attention required"
fi
if $TEST_CONNECTIVITY && [ "$JAMF_PRESENT" = true ] && [ "$JAMF_CONNECTIVITY" != "passed" ]; then
  OVERALL="Attention required"
fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "mdm_enrolled": $MDM_ENROLLED,
  "automated_device_enrollment": $ADE_ENROLLED,
  "bootstrap_token_escrowed": $BOOTSTRAP_ESCROWED,
  "configuration_profile_indicators": ${PROFILE_COUNT:-0},
  "jamf_present": $JAMF_PRESENT,
  "jamf_version": "$JAMF_VERSION",
  "jamf_connectivity_test": "$JAMF_CONNECTIVITY",
  "enrollment_status": "$ENROLLMENT_RAW",
  "overall_status": "$OVERALL"
}
EOF

printf '\nmacOS MDM and Jamf diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
