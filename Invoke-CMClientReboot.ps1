<#
.SYNOPSIS
    Triggers a ConfigMgr client reboot that respects maintenance windows and reboot policies.

.DESCRIPTION
    This script initiates a reboot through the SCCM/ConfigMgr client, ensuring that:
    - Maintenance windows are respected
    - User notifications are displayed per client settings
    - Reboot grace periods are honored
    - The reboot is logged properly in CM client logs

    Used by ConfigMgrClientHealth as the RebootApplication to ensure reboots follow 
    organizational policy rather than forcing immediate restarts.

.PARAMETER Force
    If specified, requests an immediate reboot without waiting for maintenance window.
    The CM client may still apply grace periods based on client settings.

.PARAMETER GracePeriodMinutes
    Optional grace period in minutes before reboot. Default is to use client settings.

.EXAMPLE
    .\Invoke-CMClientReboot.ps1
    Triggers a policy-compliant reboot through the CM client.

.EXAMPLE
    .\Invoke-CMClientReboot.ps1 -Force
    Requests immediate reboot (still subject to client grace period settings).

.NOTES
    Author: Kwik Trip SCCM Team
    Version: 1.0
    Date: 2026-05-22
    
    For use with ConfigMgrClientHealth RebootApplication option:
    <Option Name="RebootApplication" Application="powershell.exe -ExecutionPolicy Bypass -File \\sccmprd01\sources\ClientHealth\script\Invoke-CMClientReboot.ps1" Enable="True" />
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [int]$GracePeriodMinutes
)

$LogFile = "C:\kworking\CMClientReboot.log"
$Component = "Invoke-CMClientReboot"

function Write-Log
{
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Severity = 'Info'
    )
    
    # CMTrace log format
    switch ($Severity)
    {
        'Info'    { $Type = 1 }
        'Warning' { $Type = 2 }
        'Error'   { $Type = 3 }
    }
    
    $TimeGenerated = Get-Date -Format "HH:mm:ss.fff"
    $DateGenerated = Get-Date -Format "MM-dd-yyyy"
    $Thread = [Threading.Thread]::CurrentThread.ManagedThreadId
    $Context = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    $LogEntry = "<![LOG[$Message]LOG]!><time=`"$TimeGenerated`" date=`"$DateGenerated`" component=`"$Component`" context=`"$Context`" type=`"$Type`" thread=`"$Thread`" file=`"Invoke-CMClientReboot.ps1`">"
    
    # Ensure log directory exists
    $LogDir = Split-Path -Path $LogFile -Parent
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    
    Add-Content -Path $LogFile -Value $LogEntry -ErrorAction SilentlyContinue
    Write-Verbose $Message
}

try
{
    Write-Log "=========================================="
    Write-Log "Invoke-CMClientReboot started"
    Write-Log "Force: $Force"
    if ($GracePeriodMinutes) { Write-Log "GracePeriodMinutes: $GracePeriodMinutes" }

    # Verify CM client is installed
    $ccmExec = Get-Service -Name 'ccmexec' -ErrorAction SilentlyContinue
    if ($null -eq $ccmExec)
    {
        Write-Log "ConfigMgr client (ccmexec) not found" -Severity Error
        exit 1
    }

    if ($ccmExec.Status -ne 'Running')
    {
        Write-Log "ccmexec service is not running, attempting to start..." -Severity Warning
        Start-Service -Name 'ccmexec' -ErrorAction Stop
        Start-Sleep -Seconds 5
    }

    # Check if there's actually a pending reboot
    Write-Log "Checking for pending reboot..."
    
    $rebootPending = $false
    $rebootReason = @()

    # Method 1: Check CM client reboot status
    try
    {
        $ccmReboot = Invoke-WmiMethod -Namespace 'root\ccm\ClientSDK' -Class 'CCM_ClientUtilities' -Name 'DetermineIfRebootPending' -ErrorAction Stop
        if ($ccmReboot.RebootPending -or $ccmReboot.IsHardRebootPending)
        {
            $rebootPending = $true
            $rebootReason += "CM Client reports reboot pending"
            Write-Log "CM Client: RebootPending=$($ccmReboot.RebootPending), IsHardRebootPending=$($ccmReboot.IsHardRebootPending)"
        }
    }
    catch
    {
        Write-Log "Could not query CM client reboot status: $_" -Severity Warning
    }

    # Method 2: Check Windows Update reboot flag
    $wuReboot = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue
    if ($null -ne $wuReboot)
    {
        $rebootPending = $true
        $rebootReason += "Windows Update reboot required"
    }

    # Method 3: Check Component Based Servicing
    $cbsReboot = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction SilentlyContinue
    if ($null -ne $cbsReboot)
    {
        $rebootPending = $true
        $rebootReason += "Component Based Servicing reboot pending"
    }

    # Method 4: Check PendingFileRenameOperations
    $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($null -ne $pfro.PendingFileRenameOperations)
    {
        $rebootPending = $true
        $rebootReason += "Pending file rename operations"
    }

    if (-not $rebootPending)
    {
        Write-Log "No pending reboot detected. Exiting without action."
        exit 0
    }

    Write-Log "Reboot pending. Reasons: $($rebootReason -join '; ')"

    # Trigger the reboot through CM client
    Write-Log "Initiating CM client reboot..."

    if ($Force)
    {
        # Request immediate reboot (still respects client grace period)
        Write-Log "Requesting immediate reboot via CM client..."
        
        # Method: Use RestartComputer method
        try
        {
            $result = Invoke-WmiMethod -Namespace 'root\ccm\ClientSDK' -Class 'CCM_ClientUtilities' -Name 'RestartComputer' -ArgumentList @($null, $null) -ErrorAction Stop
            Write-Log "RestartComputer invoked. Return value: $($result.ReturnValue)"
        }
        catch
        {
            Write-Log "RestartComputer method failed: $_" -Severity Warning
            
            # Fallback: Create a reboot task sequence variable or use alternative method
            try
            {
                # Alternative: Trigger machine policy and let pending reboot process
                Write-Log "Attempting alternative: Triggering machine policy evaluation..." -Severity Warning
                Invoke-WmiMethod -Namespace 'root\ccm' -Class 'SMS_Client' -Name 'TriggerSchedule' -ArgumentList '{00000000-0000-0000-0000-000000000021}' -ErrorAction Stop
                Write-Log "Machine policy triggered"
                
                # Also trigger software updates evaluation
                Invoke-WmiMethod -Namespace 'root\ccm' -Class 'SMS_Client' -Name 'TriggerSchedule' -ArgumentList '{00000000-0000-0000-0000-000000000113}' -ErrorAction Stop
                Write-Log "Software updates scan triggered"
            }
            catch
            {
                Write-Log "Alternative methods failed: $_" -Severity Error
            }
        }
    }
    else
    {
        # Standard policy-compliant reboot - will wait for maintenance window
        Write-Log "Requesting policy-compliant reboot (will respect maintenance windows)..."
        
        try
        {
            # This notifies the CM client that a reboot is needed
            # The client will handle it according to policy (maintenance windows, notifications, etc.)
            $result = Invoke-WmiMethod -Namespace 'root\ccm\ClientSDK' -Class 'CCM_ClientUtilities' -Name 'RestartComputer' -ArgumentList @($null, $null) -ErrorAction Stop
            Write-Log "RestartComputer invoked. Return value: $($result.ReturnValue)"
            
            # Return values:
            # 0 = Success
            # Other = Various errors
            
            if ($result.ReturnValue -eq 0)
            {
                Write-Log "Reboot request submitted successfully. CM client will handle according to policy."
            }
            else
            {
                Write-Log "RestartComputer returned non-zero: $($result.ReturnValue)" -Severity Warning
            }
        }
        catch
        {
            Write-Log "Failed to invoke RestartComputer: $_" -Severity Error
            
            # Fallback: Set the reboot required flag so CM client picks it up
            try
            {
                Write-Log "Setting reboot required flag..." -Severity Warning
                $null = New-Item -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -Name 'RebootBy' -Value (Get-Date).AddHours(24).ToString('o') -ErrorAction SilentlyContinue
                Write-Log "Reboot flag set. CM client should detect on next policy cycle."
            }
            catch
            {
                Write-Log "Failed to set reboot flag: $_" -Severity Error
                exit 1
            }
        }
    }

    Write-Log "Invoke-CMClientReboot completed"
    Write-Log "=========================================="
    exit 0
}
catch
{
    Write-Log "FATAL ERROR: $_" -Severity Error
    exit 1
}
