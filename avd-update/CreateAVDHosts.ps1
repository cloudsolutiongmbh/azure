####################################
#
# These variables need to be customized for this specific deployment /customer
####################################
$Tenant = “Azure Tenant ID” 
$SubscriptionId = "Azure Subscription ID" 
$VMPoolSize = “Number of Hosts to create (1-xxx)"
$VMLocation = "VM location"
$HostPoolLocation = "AVD Host Pool location"
$DomainToJoin = "AD Domain to join"
$OuTOJoin = "AD OU for session hosts"
$DomainJoinAccount = "AD Domain Join Account"
$DomainJoinAccountPassword = "AD Domain Join Account Password"
$VMLocalAdminUser = "VM local admin"
$VMLocalAdminPassword = "VM local admin password"
$sigGalleryName = "Shared Image Gallery name"
$imageDefName = "Image definition name"
$resourcegroupname = "Azure resource group name"
$VMSize = "Azure VM Size"
$hostpoolname = "AVD Host Pool name"
$WorkspaceName = "AVD Workspace name"
$VMPrefix = "VM Prefix"
$PostScriptURL = "URL to Post deploy script"
$PostDeployScriptName = "Name of post deploy script"


# Define modules and module versions tested for use with this script
$module = "Az"
if (!(Get-Module -ListAvailable -Name $module)) {
    Install-Module -Name $module -Force
} 
else {
    Import-Module -Name $module
}


# Login with an Azure AD credential 
Connect-AzAccount -Tenant $Tenant | Out-Null
Select-AzSubscription $SubscriptionId | Out-Null


## Generate VM's names
write-host "Generating VM Names..."

# Check if there are already hosts with the prefix (and store the "index" numbers of existing hosts)
$ExistingVMList = @()
Foreach ( $ExistingVM in (Get-AZVM).name ) {

    If ( $ExistingVM.startswith("$VMPrefix") ) { 

        [int]$Index = $ExistingVM.Replace("$VMPrefix-", "")
        $ExistingVMList += $Index
    
    }

}

# Check what the highest number in the VM index list is, if nothing is found set the first number to 1, else continue numbering upward of highest number found.
If ( $ExistingVMList ) { 

    $VMPoolSizeMin = ($ExistingVMList | Measure-Object -Maximum).Maximum
    # Increment the highest number found by 1
    $VMPoolSizeMin++

}
Else {

    $VMPoolSizeMin = 1

}

# Generate host names for VM's to be created
$VMHostNameList = @()
$VMPoolSizeMin..($VMPoolSize + ($VMPoolSizeMin - 1)) | ForEach-Object { 
    
    $VMHostNameList += $VMPrefix + - $_

}

# create a registration token to authorize a session host to join the host pool and save it to a new file on your local computer. You can specify how long the registration token is valid by using the -ExpirationHours parameter.
New-AzWvdRegistrationInfo -ResourceGroupName $resourcegroupname -HostPoolName $hostpoolname -ExpirationTime $((get-date).ToUniversalTime().AddHours(24).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')) | Out-Null


# Store the registration token to a variable, which you will use To register the virtual machines to the Windows Virtual Desktop host pool.
$WVDRegistrationToken = Get-AzWvdRegistrationInfo -ResourceGroupName $resourcegroupname -HostPoolName $hostpoolname

# Add user groups to the default desktop app group for the host pool
If ( $ADGroupsToAdd ) {

    foreach ( $ADGroup in $ADGroupsToAdd ) {

        $AZADGroup = Get-AzADGroup -DisplayName $ADGroup
        $Resourcename = $Hostpoolname + "-DAG"

        New-AzRoleAssignment -ObjectId $AZADGroup.id -RoleDefinitionName "Desktop Virtualization User" -ResourceName $Resourcename -ResourceGroupName $resourcegroupname -ResourceType 'Microsoft.DesktopVirtualization/applicationGroups' -ErrorAction Stop
    
    }

}



# Build a single string from the values to pass as argument to the VM install script (command delimiter is ASCII character 254 and line delimiter is char 255)
$String = 'OuTOJoin' + "$([char]254)" + $OuTOJoin + "$([char]255)"
$String = $String + 'DomainToJoin' + "$([char]254)" + $DomainToJoin + "$([char]255)"
$string = $String + 'Registrationtoken' + "$([char]254)" + $WVDRegistrationToken.Token + "$([char]255)"
$string = $String + 'DomainJoinAccount' + "$([char]254)" + $DomainJoinAccount + "$([char]255)"
$string = $String + 'DomainJoinAccountPassword' + "$([char]254)" + $DomainJoinAccountPassword + "$([char]255)"

# Encode the argument to pass, to an UTF8 encoded string (to avoid breaks with "strange" characters)
$ArgumentToPass = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($String))

# Define the CreateVM script block (that actually creates the VM)
# note: when using variables from outside the block we use $variable
$CreateVM = {

    param(

        [Parameter(Position = 1)]
        [string]$VMHostname

    )

    # Define the NIC name based on the VMHostname
    $VMNICName = $VMHostname + "-nic"
    $PublicIPAddressName = $VMHostname + "-pip"

    $PIP = New-AzPublicIpAddress -Name $PublicIPAddressName -ResourceGroupName $Using:ResourceGroupName -Location $Using:vmlocation -AllocationMethod Static

    # Create NICs
    $NIC = New-AzNetworkInterface -Name $VMNICName -ResourceGroupName $Using:ResourceGroupName -Location $Using:VMLocation -SubnetId $Using:VMVirtualNetworkSubnetObjectID -PublicIpAddressId $PIP.Id -Force
    Get-AzResource -Name $VMNICName -ResourceGroupName $Using:resourcegroupname | Out-Null
    

    # Create credential object for local admin
    $VMLocalAdminSecurePassword = ConvertTo-SecureString $Using:VMLocalAdminPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($Using:VMLocalAdminUser, $VMLocalAdminSecurePassword);

    $imageDefinition = Get-AzGalleryImageDefinition `
        -GalleryName $Using:sigGalleryName `
        -ResourceGroupName $Using:ResourceGroupName `
        -Name $Using:imageDefName | Select-Object ID

    $vmConfig = New-AzVMConfig `
        -VMName $vmHostName `
        -VMSize $Using:VMSize | `
        Set-AzVMOperatingSystem -Windows -ComputerName $VMHostname -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate | `
        Set-AzVMSourceImage -Id $imageDefinition.Id | `
        Add-AzVMNetworkInterface -Id $nic.Id

    # Create a virtual machine
    New-AzVM `
        -ResourceGroupName $Using:resourceGroupName `
        -Location $Using:vmlocation `
        -VM $vmConfig

    # Content will land in "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\x.xx.x\Downloads\x
    Set-AzVMCustomScriptExtension `
        -Name "WVDVMPostdeployactions" `
        -Location $Using:VMLocation `
        -ResourceGroupName $Using:resourcegroupname `
        -VMName $VMHostname `
        -FileUri $Using:PostScriptURL `
        -Run $Using:PostDeployScriptName `
        -Argument $Using:ArgumentToPass `
        -ErrorAction Stop | Out-Null


    # Read the status of the custom script extension
    $Status = Get-AzVMDiagnosticsExtension -ResourceGroupName $Using:resourcegroupname -VMName $VMHostname -Name WVDVMPostdeployactions -status
    If ( $Status.ProvisioningState -eq "Failed") {
        Write-host "Failed" -ForegroundColor Red
    }
    # Display the output of the custom script extension
    $Status.SubStatuses.message 

    # remove the custom script extension (and with that, the local files on cached on the VM)
    Get-AzVMCustomScriptExtension -ResourceGroupName $Using:resourcegroupname -VMName $VMHostname -Name "WVDVMPostdeployactions" | Remove-AzVMCustomScriptExtension -force
    Remove-AzureVMBGInfoExtension -VM $VMHostname

    # Restart the VM to complete installation
    Restart-azvm -ResourceGroupName $resourcegroupname -name $VMHostname | Out-Null

}

# Clear the job list var (just in case)
$Joblist = $null

# Loopt through the list of VMhostnames to create
Foreach ( $VMHostname in $VMHostNameList ) {

    # Create/update a list of names of jobs (started by this script) for easy deletion afterwards
    $Jobname = "CreateVM " + $VMHostname + " JobID:" + (Get-Random)
    If ( -not ($Joblist) ) { 

        $Joblist = @($Jobname) 

    }
    Else { 

        $JobList = @(
    
            $Joblist
            $Jobname
    
        )

    }
    
    # Execute the job(s)
    $JobCreate = Start-Job -Name $Jobname -ScriptBlock $CreateVM -ArgumentList $VMHostname

}

### Wait for all jobs to complete

# Get the number of jobs created
$JobsRunning = ( $Joblist | Measure-Object ).count

# Define all possible complete states that a job can be in (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-job?view=powershell-7.1)
$StateComplete = @( "Completed", "Failed", "Stopped", "Blocked", "Suspended", "Disconnected" )
# $StateNotComplete = @( "NotStarted", "Running", "Suspending", "Stopping" )

# Overwrite existing measuring vars
$JobsDone = $null
$Jobsfound = $null

# Start a while loop to check if all jobs have finished
While ( $JobsDone -ne "YES" ) {

    $Jobsfound = $JobsRunning
    ForEach ( $Jobname in $Joblist ) {

        If ( $StateComplete -contains (Get-Job -Name $Jobname).state ) { 
            
            $Jobsfound--
        
        }

    }

    # Break the loop if all jobs have reached the status set in $StateComplete
    If ( $Jobsfound -eq 0 ) {

        $JobsDone = "YES"

    }

    Start-Sleep 5

}

# Remove jobs
Foreach ( $Job in $Joblist ) { 
    Get-Job -Name $Job | Remove-job
}

# Cleanup temp files
Cleanup

Write-host "done"
