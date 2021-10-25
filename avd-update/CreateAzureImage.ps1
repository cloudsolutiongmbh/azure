########################
###    VARIABELN     ###
########################
$sigGalleryName= "Shared Image Gallery name"
$imageDefName ="Image definition name"
$imageResourceGroup="Azure Ressource group name"
$location="Azure datacenter location"
$imageTemplateName="Image template name"
$runOutputName="Shared image gallery output name"
$replRegion2="Azure location replication"
$skuVersion ="Windows SKU Version like 21h1-evd" 

################################################################################################
### 1. IF NOT ALREADY PRESENT REGISTER THE AZURE IMAGE BUILDER SERVICE WHILST IN PREVIEW     ###
################################################################################################
Install-Module Az -Force
Install-Module -Name Az.ImageBuilder
Install-Module -Name Az.ManagedServiceIdentity
Import-Module Az.ImageBuilder
Import-Module Az.ManagedServiceIdentity

Connect-AzAccount

# Register for Azure Image Builder Feature
Register-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages

do{
    Clear-Variable -Name status
    $status = Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages
}while ($status.RegistrationState -ne "Registered")

# check you are registered for the providers, ensure RegistrationState is set to 'Registered'.
if($state = "Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages | Select-Object RegistrationState" -ne "Registered"){Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages}
if($state = "Get-AzResourceProvider -ProviderNamespace Microsoft.Storage | Select-Object RegistrationState" -ne "Registered"){Register-AzResourceProvider -ProviderNamespace Microsoft.Storage}
if($state = "Get-AzResourceProvider -ProviderNamespace Microsoft.Compute | Select-Object RegistrationState" -ne "Registered"){Register-AzResourceProvider -ProviderNamespace Microsoft.Compute}
if($state = "Get-AzResourceProvider -ProviderNamespace Microsoft.KeyVault | Select-Object RegistrationState" -ne "Registered"){Register-AzResourceProvider -ProviderNamespace Microsoft.KeyVault}

################################################################################################
### 2. AIB - Azure Image Builder                                                             ###
################################################################################################
# Get existing context
$currentAzContext = Get-AzContext
# Get your current subscription ID. 
$subscriptionID=$currentAzContext.Subscription.Id

##CREATE A USER ASSIGNED IDENTITY, THIS WILL BE USED TO ADD THE IMAGE TO THE SIG
# setup role def names, these need to be unique
$timeInt=$(get-date -UFormat "%s")
$imageRoleDefName="Azure Image Builder Image Def"+$timeInt
$identityName="aibIdentity"+$timeInt
$identityName="aibIdentity"

# Create identity
# New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName
New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName
$identityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId

## ASSIGN PERMISSIONS FOR THIS IDENTITY TO DISTRIBUTE IMAGES
$aibRoleImageCreationUrl="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$aibRoleImageCreationPath = "aibRoleImageCreation.json"

# Download config
Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $aibRoleImageCreationPath

# Create the  role definition
New-AzRoleDefinition -InputFile  ./aibRoleImageCreation.json
# Grant role definition to image builder service principal
New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"


################################################################################################
### 3. CREATE THE SHARED IMAGE GALLERY                                                       ###
################################################################################################
# Create the gallery
New-AzGallery `
   -GalleryName $sigGalleryName `
   -ResourceGroupName $imageResourceGroup  `
   -Location $location

# 3.1 Create the image "definition", Windows 10 Multi Session with M365 Apps
New-AzGalleryImageDefinition `
   -GalleryName $sigGalleryName `
   -ResourceGroupName $imageResourceGroup `
   -Location $location `
   -Name $imageDefName `
   -OsState generalized `
   -OsType Windows `
   -Publisher 'CloudSolutionGmbH' `
   -Offer 'Windows10EVDM365' `
   -Sku '21h1-evd'

# Get Windows 10 SKU
#Get-AzVMImageSku -Location $location -PublisherName MicrosoftWindowsDesktop -Offer office-365

## 3.2 DOWNLOAD AND CONFIGURE THE TEMPLATE WITH YOUR PARAMS
$templateUrl="https://raw.githubusercontent.com/cloudsolutiongmbh/azure/main/avd-update/armTemplate.json"
$templateFilePath = "armTemplateWVD.json"

Invoke-WebRequest -Uri $templateUrl -OutFile $templateFilePath -UseBasicParsing

((Get-Content -path $templateFilePath -Raw) -replace '<subscriptionID>',$subscriptionID) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<rgName>',$imageResourceGroup) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<runOutputName>',$runOutputName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imageDefName>',$imageDefName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<sharedImageGalName>',$sigGalleryName) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<region1>',$location) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '<imgBuilderId>',$identityNameResourceId) | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '120','420') | Set-Content -Path $templateFilePath
((Get-Content -path $templateFilePath -Raw) -replace '20h1-ent','21h1-evd') | Set-Content -Path $templateFilePath

$json = Get-Content -path $templateFilePath -Raw | Convertfrom-Json
$language = [PSCustomObject]@{"type" = "PowerShell"; "name" = "installLanguage"; "runElevated" = $true; "runAsSystem" = $true; "scripturi" = "https://raw.githubusercontent.com/cloudsolutiongmbh/azure/main/avd-update/install-language.ps1"} 
$customization = [PSCustomObject]@{"type" = "PowerShell"; "name" = "customization"; "runElevated" = $true; "runAsSystem" = $true; "scripturi" = "https://raw.githubusercontent.com/cloudsolutiongmbh/azure/main/avd-update/customization.ps1"} 
$json.resources.properties.customize += $language
$json.resources.properties.customize += $customization
$json | ConvertTo-Json -Depth 32 | Out-File $templateFilePath

##CREATE THE IMAGE VERSION
New-AzResourceGroupDeployment `
-ResourceGroupName $imageResourceGroup `
-TemplateFile $templateFilePath `
-api-version "2020-02-14" `
-imageTemplateName $imageTemplateName `
-svclocation $location

##BUILD THE IMAGE
Start-AzImageBuilderTemplate `
-ResourceGroupName $imageResourceGroup `
-Name $imageTemplateName `
-NoWait

$getStatus=$(Get-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name $imageTemplateName)

$getStatus | Format-List -Property *
# these show the status the build
$getStatus.LastRunStatusRunState 
$getStatus.LastRunStatusMessage
$getStatus.LastRunStatusRunSubState

################################################################################################
### 4. CLEANUP / ERST NACH DEM ERFOLGREICHEN BUILD ANWENDEN                                  ###
################################################################################################
Remove-AzImageBuilderTemplate -ResourceGroupName $imageResourceGroup -Name wvd10ImageTemplate
Remove-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefName -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"
## remove definitions
Remove-AzRoleDefinition -Name "$identityNamePrincipalId" -Force -Scope "/subscriptions/$subscriptionID/resourceGroups/$imageResourceGroup"
## delete identity
Remove-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName -Force
Remove-AzResourceGroup $imageResourceGroup -Force
