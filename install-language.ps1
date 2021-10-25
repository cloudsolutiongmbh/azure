########################
###    VARIABELN     ###
########################
$architecture = "x64" 
$languages = @('de-DE')
$driveLetter = "Y:"


write-host 'AIB Customization: Downloading ISO starting'
New-Item -Path C:\\ -Name windowslanguage -ItemType Directory -ErrorAction SilentlyContinue

$LocalPath = 'C:\\windowslanguage'
$file = '19041.1.191206-1406.vb_release_CLIENTLANGPACKDVD_OEM_MULTI.iso'
$url = "https://software-download.microsoft.com/download/pr/" + $file
$outputPath = $LocalPath + '\' + $file

Invoke-WebRequest -Uri $url -OutFile $outputPath
write-host 'AIB Customization: Download ISO finished'

write-host 'AIB Customization: ISO mounting'
# Mount the ISO, without having a drive letter auto-assigned
$diskImg = Mount-DiskImage -ImagePath $outputPath  -NoDriveLetter
# Get mounted ISO volume
$volInfo = $diskImg | Get-Volume
# Mount volume with specified drive letter (requires Administrator access)
mountvol $driveLetter $volInfo.UniqueId
write-host 'AIB Customization: ISO mounted'

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -Verbose

###################################################
# Install Language pack  Win10 1809 and higher
# Created by Patrick van den Born (vandenborn.it)
################################################

write-host 'AIB Customization: Start language installation'

$installed_lp = New-Object System.Collections.ArrayList

foreach ($language in $languages) {
    #check if files exist
    $appxfile = $driveletter + "\LocalExperiencePack\" + $language + "\" + "\LanguageExperiencePack." + $language + ".Neutral.appx"
    $licensefile = $driveletter + "\LocalExperiencePack\" + $language + "\" + "\License.xml"
    $cabfile = $driveletter + "\" + $architecture + "\" + "\LangPacks\Microsoft-Windows-Client-Language-Pack_" + $architecture + "_" + $language + ".cab"    
   
    if (!(Test-Path $appxfile)) {
        Write-Host $language " - File missing: $appxfile" -ForegroundColor Red
        Write-Host "Skipping installation of "  + $language.Name
    } elseif (!(Test-Path $licensefile)) {
        Write-Host $language " - File missing: $licensefile" -ForegroundColor Red
        Write-Host "Skipping installation of "  + $language.Name
    } elseif (!(Test-Path $cabfile)) {
        Write-Host $language " - File missing: $cabfile" -ForegroundColor Red
        Write-Host "Skipping installation of "  + $language.Name
    } else {
        Write-Host $language " - Installing $cabfile" -ForegroundColor Green
        Start-Process -FilePath "dism.exe" -WorkingDirectory "C:\Windows\System32" -ArgumentList "/online /Add-Package /PackagePath=$cabfile /NoRestart" -Wait

        Write-Host $language " - Installing $appxfile" -ForegroundColor Green
        Start-Process -FilePath "dism.exe" -WorkingDirectory "C:\Windows\System32" -ArgumentList "/online /Add-ProvisionedAppxPackage /PackagePath=$appxfile /LicensePath=$licensefile /NoRestart" -Wait

        Write-Host $language " - CURRENT USER - Add language to preffered languages (User level)" -ForegroundColor Green
        $prefered_list = Get-WinUserLanguageList
        $prefered_list.Add($language)
        Set-WinUserLanguageList($prefered_list) -Force

        $installed_lp.Add($language)
    }
}

Write-Host "$systemlocale - Setting the system locale" -ForegroundColor Green
Set-WinSystemLocale -SystemLocale de-DE

write-host 'AIB Customization: Finished Language installation' 

# Unmount drive
DisMount-DiskImage -ImagePath $outputPath 

# Cleanup leftover files
Remove-Item -Recurse -Force $LocalPath
