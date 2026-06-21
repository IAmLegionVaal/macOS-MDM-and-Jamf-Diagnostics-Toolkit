# macOS MDM and Jamf Diagnostics Toolkit

A macOS support toolkit for diagnosing and repairing common MDM enrolment, managed-client and Jamf framework problems.

## Diagnostic script

```bash
chmod +x src/macos_mdm_jamf_diagnostics.sh
sudo ./src/macos_mdm_jamf_diagnostics.sh
```

Include the Jamf connectivity check:

```bash
sudo ./src/macos_mdm_jamf_diagnostics.sh --test-connectivity --hours 48
```

## Repair script

Preview service repair:

```bash
chmod +x src/macos_mdm_jamf_repair.sh
sudo ./src/macos_mdm_jamf_repair.sh --repair --dry-run
```

Restart MDM and managed-client services:

```bash
sudo ./src/macos_mdm_jamf_repair.sh --repair
```

Renew MDM enrolment:

```bash
sudo ./src/macos_mdm_jamf_repair.sh --renew-enrollment
```

Submit Jamf inventory or run a custom policy event:

```bash
sudo ./src/macos_mdm_jamf_repair.sh --jamf-recon
sudo ./src/macos_mdm_jamf_repair.sh --jamf-policy repair-event
```

Reapply Jamf management settings:

```bash
sudo ./src/macos_mdm_jamf_repair.sh --jamf-manage
```

## What the repair does

- Restarts MDM, profiles and ManagedClient processes and launch services.
- Can start Apple's supported enrolment-renewal workflow.
- Can run Jamf inventory, management and one selected policy event.
- Verifies enrolment, bootstrap-token indicators, management processes and Jamf connectivity after repair.
- Supports confirmation prompts, dry-run, logs and clear exit codes.

## Safety and privacy

The tool does not unenrol the Mac, remove profiles, delete the Jamf framework or expose management credentials. Reports may contain organisation names, identifiers, server names and management URLs and should be reviewed before sharing.

## Author

Dewald Pretorius — L2 IT Support Engineer
