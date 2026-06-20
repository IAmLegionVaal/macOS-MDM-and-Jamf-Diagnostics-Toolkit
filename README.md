# macOS MDM and Jamf Diagnostics Toolkit

A read-only Bash toolkit for collecting macOS MDM enrolment, configuration-profile, Jamf, management-process, log, certificate, and connectivity evidence.

## Checks performed

- Automated Device Enrolment and MDM status
- Bootstrap-token support and escrow state
- Installed configuration-profile inventory
- MDM client and profile service processes
- Jamf binary discovery, version, policy state, and log evidence
- Jamf launch daemons and framework files
- APNs and device-management certificate indicators
- Recent `mdmclient`, profiles, ManagedClient, and Jamf events
- Optional Jamf server connectivity test
- Text, CSV, and JSON reports

## Usage

```bash
chmod +x src/macos_mdm_jamf_diagnostics.sh
sudo ./src/macos_mdm_jamf_diagnostics.sh
```

Include the read-only Jamf connectivity check:

```bash
sudo ./src/macos_mdm_jamf_diagnostics.sh --test-connectivity --hours 48
```

## Safety

The toolkit does not enrol or unenrol the Mac, renew profiles, run Jamf policies, submit inventory, rotate certificates, remove frameworks, or modify management settings.

## Privacy

Reports may contain organisation names, profile identifiers, internal server names, usernames, device identifiers, and management URLs. Review output before sharing.

## Requirements

- macOS 12 or later recommended
- Bash 3.2+
- Administrator privileges for complete profile and log evidence
- Jamf is optional; the script handles systems where it is absent

## Author

Dewald Pretorius — L2 IT Support Engineer
