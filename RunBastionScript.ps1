<#
.SYNOPSIS
  This script allows the users to login into a SSH Bastion Host using an easy way.
  Instead of manually writing the SSH command, the user only configure its username inside the file and the script
  will ask its password using a Visual Basic input box.
.NOTES
  Version:        1.0
  Author:         Darnley Costa
  Creation Date:  Dec/31/2019
  Purpose/Change: Initial script development
#>
param([switch]$Elevated)

#---------------------------------------------------------[Initializations]--------------------------------------------------------
$Username = 'username'; # Put the account username
$Password = $null; # Optional

# Configure the tunnels to connect to
$Tunnels = @(
    @{ RemoteHost = '255.255.255.255'; RemotePort = 8080; LocalPort = 32400 },
    @{ RemoteHost = '255.255.255.0'; RemotePort = 8081; LocalPort = 32400 }
);

#----------------------------------------------------------[Declarations]----------------------------------------------------------
$RemoteServerHost = 'hostname.com';
$RemoteServerPort = 22;

$MaxRetryCount = 3;

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function SetPasswordUsingVisualBasic {
    [void][Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')

    $title = 'Account Credentials'
    $msg = 'Enter your password for account:'

    RETURN [Microsoft.VisualBasic.Interaction]::InputBox($msg, $title)
}

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Test-CommandExists {
    Param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'

    try {
        if (Get-Command $command) {
            RETURN $true
        }
    }
    Catch {
        RETURN $false
    }
    Finally {
        $ErrorActionPreference = $oldPreference
    }
}

function RunScriptAsAdministrator {
    if ((Test-Admin) -eq $false) {
        if ($elevated) {
            # tried to elevate, did not work, aborting
        } 
        else {
            Write-Host 'Running application with privileges' -ForegroundColor Gray
            Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
        }

        exit
    }
}

function ChocolateyInstall {
    param ($package)

    RunScriptAsAdministrator

    Start-Process choco.exe -ArgumentList ("install $package")
}

function InstallDependencies {
    # Verify for Chocolatey installation
    If ((Test-CommandExists choco) -eq $false) {
        Write-Host 'Chocolatey not installed. Initializing installation...' -ForegroundColor Green

        RunScriptAsAdministrator

        Set-ExecutionPolicy Bypass -Scope Process -Force;
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    else {
        Write-Host 'Chocolatey installed' -ForegroundColor DarkGreen
    }

    # Verify for SSH installation
    If ((Test-CommandExists ssh) -eq $false) {
        Write-Host 'SSH not installed. Initializing installation...' -ForegroundColor Green
        ChocolateyInstall openssh
    }
    else {
        Write-Host 'SSH installed' -ForegroundColor DarkGreen
    }
}

function MountSshCommand {
    param($sshTunnels)

    $TunnelsStr = ''

    foreach ($tunnel in $Tunnels) {
        $TunnelsStr += "-R $($tunnel.LocalPort):$($tunnel.RemoteHost):$($tunnel.RemotePort) "
    }

    $FinalCommand = "-N $($TunnelsStr)$($Username):$($Password)@$($RemoteServerHost) -p $($RemoteServerPort)"

    RETURN $FinalCommand;
}

function RunSsh {
    Write-Host "Attempting to connect to $RemoteServerHost..." -ForegroundColor Yellow

    $ArgumentList = MountSshCommand

    Invoke-Expression "ssh.exe $ArgumentList";
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
InstallDependencies

while ([string]::IsNullOrEmpty($Password)) {
    Write-Host 'Default password not set. Asking for user interaction...' -ForegroundColor Gray

    $Password = SetPasswordUsingVisualBasic
}

Write-Host 'Password set' -ForegroundColor Gray

for ($i = 0; $i -lt $MaxRetryCount; $i++) {
    RunSsh

    if (-not ($i -eq $MaxRetryCount - 1)) {
        '---'
        Write-Host "Retrying to connect to host. $($i+1) of $($MaxRetryCount) tentatives in 5 seconds..." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 5
    }
    else {
        if ((Read-Host "`nPress [Enter] to continue or [r] to retry more 3 times").ToLowerInvariant() -eq 'r') {
            $i = 0;
        }
    }
}