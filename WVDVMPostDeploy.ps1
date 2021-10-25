



#
#
#  WVD Post deploy config script
#  Configure VM to be used as WVD
#
#  This script should reside in the storage account/container defined in the CreateWVDHostpool script
#
#
#   Changelog
#
#   0.01 - 04-04-2021 - Initial release
#
#



# Decode passed string argument 
$Decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($args[0]))

# Convert the decoded string argument to variables
$TempArr = $Decoded.split("$([char]255)")
ForEach ( $line in $TempArr) {

    If ($Line.Split("$([char]254)")[0]) {

        New-Variable -Name $Line.Split("$([char]254)")[0] -Value $Line.Split("$([char]254)")[1]

    }
 
}



#
#  Define Cleanup function
#

Function Cleanup {

    If ( Test-Path "$env:temp\Microsoft.RDInfra.RDAgent.Installer.msi" ) { 

        Remove-Item -path "$env:temp\Microsoft.RDInfra.RDAgent.Installer.msi" -Force 

    }

    If ( Test-Path "$env:temp\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi" ) { 

        Remove-item -path "$env:temp\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi" -Recurse -Force 

    }

}



# Cleanup in case a previous attempt failed
Cleanup



# Download Windows Virtual Desktop Agent
Try {
 
    (New-Object System.Net.WebClient).DownloadFile("https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv", "$env:temp\Microsoft.RDInfra.RDAgent.Installer.msi")

}
CATCH 
{

    Write-host "Error downloading Windows Virtual Desktop Agent" -ForegroundColor Red
    EXit 1

}



# Download Windows Virtual Desktop Agent Bootloader
Try {
 
    (New-Object System.Net.WebClient).DownloadFile("https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH", "$env:temp\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi")

}
CATCH 
{

    Write-host "Error downloading Windows Virtual Desktop Agent Bootloader" -ForegroundColor Red
    EXit 1

}

# Install the agents
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $env:temp\Microsoft.RDInfra.RDAgent.Installer.msi", "/quiet", "/qn", "/norestart", "/passive", "REGISTRATIONTOKEN=$Registrationtoken", "/l* $env:temp\RDAgentInstall.txt" -Wait -Passthru

Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $env:temp\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi", "/quiet", "/qn", "/norestart", "/passive", "/l* $env:temp\RDBootLoaderInstall.txt" -Wait -Passthru

# Start-Service RDAgentBootLoader # Will happen after reboot... So I will skip it for now...

# Join the machine to the domain
# Create credential object for the domain join
$DomainJoinAccountPasswordSecure = ConvertTo-SecureString $DomainJoinAccountPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($DomainJoinAccount, $DomainJoinAccountPasswordSecure);
# Join the domain
Add-Computer -DomainName $DomainToJoin -OUPath $OuTOJoin -Credential $Credential



# Cleanup temp files
Cleanup
