﻿#Software Installation
$module = "Evergreen"
if (!(Get-Module -ListAvailable -Name $module)) {
    Install-Module -Name $module -Force
} 
else {
    Import-Module -Name Evergreen
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


#Office 365
Write-Host "---------- Office 365 ----------"

$o365 = @{
    url   = "https://github.com/cloudsolutiongmbh/azure/raw/main/customization/o365setup.zip"
    path  = $folder + "\o365"
    setup = $o365.path + "\setup.exe"
    arg   = "/configure " + $o365.path + "\config.xml"
    zip   = $o365.path + "\o365setup.zip"
}

Create-Folder -path $o365.path
Download -url $o365.url -outfile $o365.zip
Expand-Archive -LiteralPath $o365.zip -DestinationPath $o365.path
Install -setup $o365.setup -arguments $o365.arg


#OneDrive Machine Installation
Write-Host "---------- OneDrive Machine Installation ----------"

$onedrive = @{
    url   = (Get-EvergreenApp -Name "MicrosoftOneDrive" | Where-Object { $_.Architecture -eq "x86" -and $_.Ring -eq "Enterprise" -and $_.Type -eq "exe" }).Uri
    path  = folder + "\onedrive"
    setup = $onedrive.path + "\OneDriveSetup.exe"
    arg   = "/silent /allusers"
}

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

#CleanUp
$paths = @($folder, "C:\optimize", "C:\teams", "C:\temp")
foreach ($path in $paths){
   if(Test-Path -Path $path){Remove-Item -Path $path -Recurse -Force}
}