# ConfigMgr Client Health

Version: 0.8.4-KT (Kwik Trip Fork)

Based on [Anders Rodland's ConfigMgr Client Health](https://github.com/AndersRodland/ConfigMgrClientHealth) v0.8.3

## Overview

PowerShell script to detect and remediate ConfigMgr client health issues. Runs as a scheduled task or via ConfigMgr baseline.

## Kwik Trip Modifications

This fork includes the following enhancements over the upstream v0.8.3:

### OS Support (GitHub Issue #81)
- Windows 11 (all builds: 21H2, 22H2, 23H2, 24H2)
- Windows Server 2022
- Windows Server 2025
- Windows 10 builds 1903 through 22H2

### 3rd Party Patching Support (GitHub Issue #80)
- Fixed registry.pol remediation to preserve WSUS settings
- Added `AcceptTrustedPublisherCerts` registry key verification
- Added PMPC certificate verification/installation

## Configuration

### Reboot Handling

The script can trigger reboots through the CM client so maintenance windows and user notifications are respected:

```xml
<Option Name="PendingReboot" StartRebootApplication="True" Enable="True" />
<Option Name="RebootApplication" Application="powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \\sccmprd01\sources\ClientHealth\script\Invoke-CMClientReboot.ps1" Enable="True" />
```

`Invoke-CMClientReboot.ps1` uses the CM client's `CCM_ClientUtilities.RestartComputer` WMI method to:
- Respect maintenance windows
- Display user notifications per client settings
- Honor reboot grace periods
- Log properly to CM client logs

| Parameter | Description |
|-----------|-------------|
| `-Force` | Request immediate reboot (still subject to client grace periods) |
| (none) | Standard policy-compliant reboot |

Logs to: `C:\kworking\CMClientReboot.log` (CMTrace format)

### 3rd Party Patching (Patch My PC)

Two new remediation options support Patch My PC and other 3rd party update publishers:

```xml
<!-- Ensures AcceptTrustedPublisherCerts registry key is set -->
<Remediation Name="TrustedPublisherCerts" Fix="True" />

<!-- Verifies/imports PMPC signing certificate -->
<Remediation Name="PMPCCertificate" Fix="True" Enable="True" CertPath="\\sccmprd01\sources\Packages\PMPCCert\PMPC.cer" />
```

| Option | Attribute | Values | Description |
|--------|-----------|--------|-------------|
| TrustedPublisherCerts | Fix | True/False | Sets `AcceptTrustedPublisherCerts=1` in registry |
| PMPCCertificate | Enable | True/False | Whether to run the certificate check |
| PMPCCertificate | Fix | True/False | Whether to import cert if missing |
| PMPCCertificate | CertPath | UNC path | Path to the .cer file |

### Registry.pol Remediation

When the script repairs a corrupt GPO cache (registry.pol), it now:
1. Deletes registry.pol
2. Runs `gpupdate /force`
3. Restarts ccmexec service
4. Sets `AcceptTrustedPublisherCerts` registry key
5. Re-verifies PMPC certificate (if enabled)
6. Refreshes SCCM update policies

This prevents 3rd party patching from breaking after GPO cache repairs.

## File Locations

| Location | Purpose |
|----------|---------|
| `\\sccmprd01\sources\ClientHealth\script\` | Script and config.xml |
| `\\sccmprd01\sources\ClientHealth\client\` | CM client installation files |
| `\\sccmprd01\sources\ClientHealth\Logs\` | Client health logs |
| `\\sccmprd01\sources\Packages\PMPCCert\` | PMPC signing certificate |

## Client Install Properties (eHTTP)

For Enhanced HTTP environments:

```xml
<ClientInstallProperty>/mp:http://sccmprd01.corp.kwiktrip.com</ClientInstallProperty>
<ClientInstallProperty>/Source:\\sccmprd01\sources\ClientHealth\client</ClientInstallProperty>
<ClientInstallProperty>SMSSITECODE=LAX</ClientInstallProperty>
<ClientInstallProperty>SMSMP=sccmprd01.corp.kwiktrip.com</ClientInstallProperty>
<ClientInstallProperty>DNSSUFFIX=corp.kwiktrip.com</ClientInstallProperty>
```

## Related Resources

- [Original ConfigMgr Client Health](https://github.com/AndersRodland/ConfigMgrClientHealth)
- [Full Documentation](https://www.andersrodland.com/configmgr-client-health/)
- Compliance Rule: `\\sccmprd01\sources\Compliance\Microsoft - Windows - Accept Trusted Publisher Certs\`
- PMPC Cert Package: `\\sccmprd01\sources\Packages\PMPCCert\`

## Changelog

See [changelog.md](changelog.md) for detailed change history.

---

This software is provided "AS IS" with no warranties. Use at your own risk.
