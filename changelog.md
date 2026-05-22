# Changelog

All notable changes to ConfigMgr Client Health will be documented in this file.

## [Unreleased] - 2026-05-22

### Added - OS Support (Issue #81)
- Added Windows 11 detection in `Get-OperatingSystem` function
- Added Windows Server 2022 detection
- Added Windows Server 2025 detection
- Added Windows 10/11 build number mappings for versions 1903 through 24H2:
  - Windows 10: 1903, 1909, 2004, 20H2, 21H1, 21H2, 22H2
  - Windows 11: 21H2, 22H2, 23H2, 24H2
- Updated Windows Update history queries for Windows 11, Server 2019, Server 2022, Server 2025
- Updated service startup type logic to include newer OS versions

### Fixed - Registry.pol Remediation (Issue #80)
- Added ccmexec service restart after registry.pol deletion and gpupdate
- Added explicit verification/remediation of `AcceptTrustedPublisherCerts` registry key after GPO cache repair
- Added re-verification of PMPC certificate in Root and TrustedPublisher stores after GPO cache repair
- Sets `HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AcceptTrustedPublisherCerts` = 1 (DWORD)
- This ensures WSUS registry settings and certificates are properly restored after registry.pol recreation
- Prevents 3rd party patching tools (like Patch My PC) from failing after GPO cache repair

### Added - Standalone TrustedPublisherCerts Check
- New `Test-TrustedPublisherCerts` function that runs independently of registry.pol repair
- New config option: `<Remediation Name="TrustedPublisherCerts" Fix="True" />`
- Ensures `AcceptTrustedPublisherCerts` registry key is always set, regardless of GPO cache state
- Catches cases where the key is missing for reasons other than registry.pol deletion

### Added - CM Client Policy-Compliant Reboot Script
- New `Invoke-CMClientReboot.ps1` script for triggering reboots through the CM client
- Respects maintenance windows and client reboot policies
- Uses `CCM_ClientUtilities.RestartComputer` WMI method
- Checks multiple reboot pending sources (CM client, Windows Update, CBS, PFRO)
- Logs to `C:\kworking\CMClientReboot.log` in CMTrace format
- Supports `-Force` parameter for immediate reboot requests

### Added - PMPC Certificate Verification
- New `Test-PMPCCertificate` function to verify/install PMPC signing certificate
- Checks if cert exists in both Root and TrustedPublisher stores
- Imports certificate from configurable network path if missing
- New config option with Enable toggle:
  ```xml
  <Remediation Name="PMPCCertificate" Fix="True" Enable="True" CertPath="\\server\share\PMPC.cer" />
  ```
- Set `Enable="False"` to disable this check entirely
- Set `Fix="False"` to report only without remediation

### Technical Details

**Issue #81 - OS Version Support**

The following OS versions are now properly detected:
- Windows 11 (all builds)
- Windows Server 2022
- Windows Server 2025
- Windows 10 builds 18362+ (1903 and later)

Build number to version mapping:
| Build | Version |
|-------|---------|
| 18362 | 1903 |
| 18363 | 1909 |
| 19041 | 2004 |
| 19042 | 20H2 |
| 19043 | 21H1 |
| 19044 | 21H2 |
| 19045 | 22H2 (Win10) |
| 22000 | 21H2 (Win11) |
| 22621 | 22H2 (Win11) |
| 22631 | 23H2 (Win11) |
| 26100 | 24H2 (Win11) |

**Issue #80 - AcceptTrustedPublisherCerts**

When the `Test-RegistryPol` function detects issues with the GPO cache (WUAHandler errors, old registry.pol, or GPO event log errors), it now:
1. Deletes registry.pol
2. Runs `gpupdate /force`
3. **NEW:** Restarts the ccmexec service
4. **NEW:** Verifies and sets `AcceptTrustedPublisherCerts` registry key if missing or incorrect
5. **NEW:** Re-verifies PMPC certificate in Root and TrustedPublisher stores (if PMPCCertificate is enabled)
6. Refreshes SCCM update policies

The ccmexec restart ensures the ConfigMgr client properly re-reads WSUS settings. The explicit registry key remediation guarantees the `AcceptTrustedPublisherCerts` value is set to `1`, which is required for 3rd party patching tools like Patch My PC to function correctly.

Registry key details:
- Path: `HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate`
- Name: `AcceptTrustedPublisherCerts`
- Value: `1`
- Type: `DWORD`

**Standalone TrustedPublisherCerts Check**

In addition to the registry.pol remediation fix, a new standalone check ensures the `AcceptTrustedPublisherCerts` key is always verified:

```xml
<Remediation Name="TrustedPublisherCerts" Fix="True" />
```

This check runs independently and will catch cases where:
- The registry key was never set
- GPO hasn't pushed the setting yet
- The key was removed by other means

The check integrates with the existing compliance rule at:
`\\sccmprd01\sources\Compliance\Microsoft - Windows - Accept Trusted Publisher Certs\`

**PMPC Certificate Verification**

New function `Test-PMPCCertificate` verifies the Patch My PC signing certificate is installed:

```xml
<Remediation Name="PMPCCertificate" Fix="True" Enable="True" CertPath="\\sccmprd01\sources\Packages\PMPCCert\PMPC.cer" />
```

| Attribute | Purpose |
|-----------|---------|
| `Enable` | `True`/`False` - Whether to run this check at all |
| `Fix` | `True`/`False` - Whether to import the cert if missing |
| `CertPath` | UNC path to the .cer file |

The function:
1. Loads the certificate from `CertPath` to get its thumbprint
2. Checks if cert exists in `Cert:\LocalMachine\Root`
3. Checks if cert exists in `Cert:\LocalMachine\TrustedPublisher`
4. If missing from either store and `Fix="True"`, imports using `certutil -addstore`

This mirrors the existing PMPC cert package at:
`\\sccmprd01\sources\Packages\PMPCCert\`
