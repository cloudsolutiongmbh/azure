#Software Installation
$module = "Evergreen"
if (!(Get-Module -ListAvailable -Name $module)) {
    Install-Module -Name $module -Force
} 
else {
    Import-Module -Name $module
}

function Create-Folder($folder) {

    if (!(Test-Path -path $folder)) {
        New-Item -ItemType directory -Path $folder -Force -ErrorAction "SilentlyContinue"
    }

}

function Download($url, $outfile) {
    Invoke-WebRequest -Uri $url -OutFile $outfile -UseBasicParsing
}

function Install($setup, $arguments) {
    Start-Process -FilePath $setup -ArgumentList $arguments
}

$folder = "C:\customization-cs"
Create-Folder -path $folder


# Office 365
Write-Host "---------- Office 365 ----------"
# Office 365 Object Configuration - download from CS Github
$o365 = @{
    url   = "https://github.com/cloudsolutiongmbh/azure/raw/main/customization/o365setup.zip"
    path  = $folder + "\o365"
    setup = $o365.path + "\setup.exe"
    arg   = "/configure " + $o365.path + "\config.xml"
    zip   = $o365.path + "\o365setup.zip"
}
# Office365 Installation
Create-Folder -path $o365.path
Download -url $o365.url -outfile $o365.zip
Expand-Archive -LiteralPath $o365.zip -DestinationPath $o365.path
Install -setup $o365.setup -arguments $o365.arg


#OneDrive Machine Installation
Write-Host "---------- OneDrive Machine Installation ----------"
# Onedrive Object Configuration - download via Evergreen
$onedrive = @{
    url   = (Get-EvergreenApp -Name "MicrosoftOneDrive" | Where-Object { $_.Architecture -eq "x86" -and $_.Ring -eq "Enterprise" -and $_.Type -eq "exe" }).Uri
    path  = folder + "\onedrive"
    setup = $onedrive.path + "\OneDriveSetup.exe"
    arg   = "/silent /allusers"
}
# Onedrive Installation
Create-Folder -path $onedrive.path
Download -url $onedrive.url -outfile $onedrive.setup
Install -setup $onedrive.setup -arguments $onedrive.arg

#FSLogix Delete Keys in Script
Write-Host "---------- CleanUp FsLogix ----------"
$fslogix_keys = @("HKLM:\Software\FSLogix\Profiles", "HKLM:\SOFTWARE\Policies\FSLogix\ODFC")

foreach ($key in $fslogix_keys) {
    $exists = Test-Path -Path $key
    if ($exists) {
        $values = Get-Item $key | Select-Object -ExpandProperty Property
        foreach ($value in $values) {
            Remove-ItemProperty -Path $key -Name $value
        }
    }

}

# MS Teams FW Rule
# based on https://msendpointmgr.com/2020/03/29/managing-microsoft-teams-firewall-requirements-with-intune/
$teams = "C:\Program Files (x86)\Microsoft\teams\current\teams.exe"
if(Test-Path -path $teams){
    if(Get-NetFirewallApplicationFilter -Program $teams -ErrorAction SilentlyContinue){
        Get-NetFirewallApplicationFilter -Program $teams -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }
    New-NetFirewallRule -DisplayName "MS Teams" -Direction Inbound -Profile Domain -Program $teams -Action Allow -Protocol Any
    New-NetFirewallRule -DisplayName "MS Teams" -Direction Inbound -Profile Public,Private -Program $teams -Action Block -Protocol Any
}

#CleanUp
$paths = @($folder, "C:\optimize", "C:\teams", "C:\temp")
foreach ($path in $paths){
   if(Test-Path -Path $path){Remove-Item -Path $path -Recurse -Force}
}
