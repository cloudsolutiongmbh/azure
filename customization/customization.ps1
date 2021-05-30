#Software Installation
$module = "Evergreen"
if (!(Get-Module -ListAvailable -Name $module)) {
    Install-Module -Name $module -Force
} 
else {
    Import-Module -Name Evergreen
}

function Create-Folder($path) {

    if (!(Test-Path -path $path)) {
        New-Item -ItemType directory -Path $path -Force -ErrorAction "SilentlyContinue"
    }

}

function Download($url, $outfile) {
    Invoke-WebRequest -Uri $url -OutFile $outfile -UseBasicParsing
}

function Install($setup, $arguments) {
    Start-Process -FilePath $setup -ArgumentList $arguments
}

$path = "C:\customization-cs"
Create-Folder -path $path


#Office 365
Write-Host "---------- Office 365 ----------"

$o365 = @{
    url   = "https://github.com/cloudsolutiongmbh/azure/raw/main/customization/o365setup.zip"
    path  = $path + "\o365"
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
    path  = $path + "\onedrive"
    setup = $onedrive.path + "\OneDriveSetup.exe"
    arg   = "/silent /allusers"
}

Create-Folder -path $onedrive.path
Download -url $onedrive.url -outfile $onedrive.setup
Install -setup $onedrive.setup -arguments $onedrive.arg

#FSLogix Delete Keys in Script
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