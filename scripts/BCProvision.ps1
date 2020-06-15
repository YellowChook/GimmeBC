Param(
    [boolean] [Parameter(Mandatory = $false)] $InstallPreReqs = $false,
    [string] [Parameter(Mandatory = $false)] $Branch = "master",
    [string] [Parameter(Mandatory = $false)] $LocalRepoPath = "C:\Dev\Repos",
    [string] [Parameter(Mandatory = $false)] $BCVersion
)

function Install-PowerAppsAdmin {
    $moduleName = "Microsoft.PowerApps.Administration.PowerShell"
    $moduleVersion = "2.0.33"
    $module = Get-Module -ListAvailable -Name $moduleName
    if (!($module.Version -ge $moduleVersion )) {
        Write-host "Module $moduleName version $moduleVersion or higher not found, installing now"
        Install-Module -Name $moduleName -RequiredVersion $moduleVersion -Force -AllowClobber
    }
    else {
        Write-host "Module $moduleName version $moduleVersion or higher Found"
    }
}


function Install-PreRequisites {
    $message = "Installing Chocolatey ...."
    Write-Host $message -ForegroundColor Green
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
 
    $message = "Installing Git ...."
    Write-Host $message -ForegroundColor Green   

    choco upgrade git.install -y
    
    $message = "Installing Azure CLI ...."
    Write-Host $message -ForegroundColor Green
    
    choco upgrade azure-cli -y 

    ## Restart PowerShell Environment to Enable Azure CLI
    Restart-PowerShell
}

function Restart-PowerShell {
    Start-Sleep -Seconds 5
    refreshenv
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User") 
    Clear-Host
}

function WriteProgressMessage {
    param (
        $TextToWrite
    )
    Write-Host
    Write-Host $TextToWrite -ForegroundColor Green
}

function DevOps-Install {
    ## Install Azure DevOps Extension
    WriteProgressMessage("Installing azure-devops extension")

    $ErrorActionPreference = "SilentlyContinue"

    az extension add --name azure-devops

    Remove-Item AzureCli.msi -ErrorAction $ErrorActionPreference

    WriteProgressMessage("Connecting to Azure DevOps Organisation")

    $adoOrg = Read-Host -Prompt "Enter the <Name> of your Azure DevOps Organisation (https://dev.azure.com/<Name>)"

    $quit = Read-Host -Prompt "You will now be redirected to a Browser to Login to your Azure DevOps Organisation - Press Enter to Continue or [Q]uit"
    if ($quit -eq "Q") {
        exit
    }

    $azSubs = az login --allow-no-subscriptions

    $Host.UI.RawUI.BackgroundColor = $bckgrnd
    Clear-Host
    Write-Host "Login complete"
    $adoCreate = Read-Host -Prompt "Would you like to [C]reate a new Project or [S]elect and existing one (Default [S])"

    if ($adoCreate -eq "C") {
        $adoProject = Read-Host -Prompt "Please enter the Name of the Project you wish to Create"

        WriteProgressMessage("Creating DevOps Project $adoProject")

        az devops project create --name $adoProject --organization=https://dev.azure.com/$adoOrg --process Agile
    }
    else {
        $selection = az devops project list --organization=https://dev.azure.com/$adoOrg --query '[value][].{Name:name}' --output json | Out-String | ConvertFrom-Json
        $choiceIndex = 0
        $options = $selection | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription "&$($choiceIndex) - $($_.Name)"; $choiceIndex++ }
        $chosenIndex = $host.ui.PromptForChoice("DevOps Project", "Select the Project you wish to use", $options, 0)
        $adoProject = $selection[$chosenIndex].Name 
    }

    Write-Host ""
    $AppName = Read-Host -Prompt "Enter the name for the BC App you wish to create"
    $adoRepo = $AppName

    WriteProgressMessage("Creating Git Repo $adoRepo")

    az devops configure --defaults organization=https://dev.azure.com/$adoOrg project=$adoProject

    $repo = az repos create --name $adoRepo | Out-String | ConvertFrom-Json
    az repos import create --git-source-url "https://github.com/YellowChook/$BCVersion.git" --repository $adoRepo

    WriteProgressMessage("Cloning Git Repo $adoRepo locally")
    Write-Host "If prompted for credentials, enter the same credentials you used for dev.azure.com"

    $FullLocalRepoPath = "$LocalRepoPath\$adoProject\$adoRepo"
    git clone $repo.webUrl "$FullLocalRepoPath"

    Set-Location -Path $FullLocalRepoPath

    WriteProgressMessage("Confirming Git User Details")

    $GitUser = git config --global user.name
    $GitEmail = git config --global user.email

    If ($GitUser -eq $null) {
        $GitUser = Read-Host "Enter your name (to use when committing changes to Git)"
        git config --global user.name $GitUser
    }

    If ($GitEmail -eq $null) {
        $GitEmail = Read-Host "Enter your email address (to use when committing changes to Git)"
        git config --global user.email $GitEmail
    }

    WriteProgressMessage("Cleaning up Git Repository")

    git checkout $branch
    git branch | select-string -notmatch $branch | foreach { git branch -D ("$_").Trim() } #Remove non-used local branches
    git branch -r | select-string -notmatch master | select-string -notmatch HEAD | foreach { git push origin --delete ("$_").Replace("origin/", "").Trim() } #Remove non-used branches from remote

    Remove-Item .git -Recurse -Force
    git init
    git add .
    git remote add origin $repo.webUrl

    chdir -Path $FullLocalRepoPath\app\

    Write-Host ""
    Write-Host ""

    WriteProgressMessage("Setting app details in Source Code")
    
    $appJsonContent = (Invoke-WebRequest "https://raw.githubusercontent.com/YellowChook/$BCVersion/$branch/app/app.json" -UseBasicParsing:$true) | ConvertFrom-Json
    $appJsonContent.id = (New-Guid)
    $appJsonContent.name = $AppName
    $appJsonContent.brief = $AppName
    $appjsonContent.description = $AppName
    $appJsonContent.contextSensitiveHelpUrl = "https://intergendocs.z23.web.core.windows.net/$($appJsonContent.id)/$($appJsonContent.version)"

    $appJsonContent | ConvertTo-Json | Set-Content -Path $FullLocalRepoPath\app\app.json

    # Rename workspace for app name
    $WorkspaceName = $AppName.Replace(' ', '')
    Rename-Item -Path "$FullLocalRepoPath\YourAppName.code-workspace" -NewName "$WorkspaceName.code-workspace"
    Rename-Item -Path "$FullLocalRepoPath\app\Translations\YourAppName.g.xlf" -NewName "$AppName.g.xlf"

    
    #$message = "Connecting to Power Platform"
    #Write-Host $message
    #$ProgressBar = New-BTProgressBar -Status $message -Value 0.70
    #New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

    #$quit = Read-Host -Prompt "Press Enter to Connect to your CDS / D365 Tenant or [Q]uit"
    #if ($quit -eq "Q") {
    #    exit
    #}

    <#
    if (!$Credentials) {
        Do {
            $Credentials = Get-Credential
        } Until (($Credentials.GetNetworkCredential().UserName -ne "") -and ($Credentials.GetNetworkCredential().Password -ne "")) 
    }
    if (!$username) {
        $username = $Credentials.GetNetworkCredential().UserName
        $password = $Credentials.GetNetworkCredential().Password
    }

    Add-PowerAppsAccount -Username $Credentials.UserName -Password $Credentials.Password

    $Locations = Get-AdminPowerAppEnvironmentLocations
    
    $choiceIndex = 0
    $options = $Locations | ForEach-Object { write-Host "[$($choiceIndex)] $($_.LocationDisplayName)"; $choiceIndex++; }
    $geoselect = Read-Host "Please select the Geography for your Power Platform "
    $Geography = $Locations[$geoselect].LocationName

    InstallXrmModule

    $message = "Connecting to Development Environment"
    Write-Host $message
    $ProgressBar = New-BTProgressBar -Status $message -Value 0.75
    New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId
    Write-Host ""
    Write-Host "---- Please Select your Development Environment ------"
    Do {
        $conn = Connect-CrmOnlineDiscovery -Credential $Credentials
        If (!$conn.IsReady) {
            Do {
                $Credentials = Get-Credential
            } Until (($Credentials.GetNetworkCredential().UserName -ne "") -and ($Credentials.GetNetworkCredential().Password -ne "")) 
            if (!$username) {
                $username = $Credentials.GetNetworkCredential().UserName
                $password = $Credentials.GetNetworkCredential().Password
            }
        }
    } Until ($conn.IsReady) 
    

    $CreateOrSelect = Read-Host -Prompt "Development Environment : Would you like to [C]reate a New Solution or [S]elect an Existing One (Default [S])"
    if ($CreateOrSelect -eq "C") {

        $message = "Creating Solution and Publisher"
        Write-Host $message
        $ProgressBar = New-BTProgressBar -Status $message -Value 0.78
        New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

        $PublisherName = Read-Host -Prompt "Enter a Name for your Solution Publisher"
        $PublisherPrefix = Read-Host -Prompt "Enter a Publisher Prefix"

        $PublisherId = New-CrmRecord -EntityLogicalName publisher -Fields @{"uniquename" = $PublisherName.Replace(' ', '').ToLower(); "friendlyname" = $PublisherName; "customizationprefix" = $PublisherPrefix.Replace(' ', '').ToLower() }

        $SolutionName = Read-Host -Prompt "Enter a Name for your Unmanaged Development Solution"
        $PubLookup = New-CrmEntityReference -EntityLogicalName publisher -Id $PublisherId.Guid
        $SolutionId = New-CrmRecord -EntityLogicalName solution -Fields @{"uniquename" = $SolutionName.Replace(' ', '').ToLower(); "friendlyname" = $SolutionName; "version" = "1.0.0.0"; "publisherid" = $PubLookup }
        $chosenSolution = $SolutionName.Replace(' ', '').ToLower()
    }
    else {

        $solutionFetch = @"
    <fetch>
    <entity name='solution' >
        <filter type='and' >
        <condition attribute='ismanaged' operator='eq' value='0' />
        <condition attribute='isvisible' operator='eq' value='1' />
        </filter>
    </entity>
    </fetch>
"@

        $solutions = (Get-CrmRecordsByFetch -conn $conn -Fetch $solutionFetch).CrmRecords

        $choiceIndex = 0
        $options = $solutions | ForEach-Object { write-host "[$($choiceIndex)] $($_.uniquename)"; $choiceIndex++; }  


        $success = $false
        do {
            $choice = read-host "Enter your selection"
            if (!$choice) {
                Write-Host "Invalid selection (null)"
            }
            else {
                $choice = $choice -as [int];
                if ($choice -eq $null) {
                    Write-Host "Invalid selection (not number)"
                }
                elseif ($choice -le -1) {
                    Write-Host "Invalid selection (negative)"
                }
                else {
                    $chosenSolution = $solutions[$choice].uniquename
                    if ($null -ne $chosenSolution) {
                        $PublisherPrefix = (Get-CrmRecord -conn $conn -EntityLogicalName publisher -Id $solutions[$choice].publisherid_Property.Value.Id -Fields customizationprefix).customizationprefix
                        $success = $true
                    }
                    else {
                        Write-Host "Invalid selection (index out of range)"
                    }
                } 
            }
        } while (!$success)
    }

    #update values in Solution files 


    $message = "Setting Configurations in Source Code"
    Write-Host $message
    $ProgressBar = New-BTProgressBar -Status $message -Value 0.80
    New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

    Write-Host "Updating config.json ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json) -replace "https://AddName.crm6.dynamics.com", $conn.ConnectedOrgPublishedEndpoints["WebApplication"] | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json) -replace "AddGeography", $Geography | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\Scripts\config.json

    Write-Host "Updating spkl.json ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\spkl.json) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\spkl.json
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\spkl.json) -replace "prefix", $PublisherPrefix.Replace(' ', '').ToLower() | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\spkl.json

    Write-Host "Updating ImportConfig.xml ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\PackageDeployer\PkgFolder\ImportConfig.xml) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\PackageDeployer\PkgFolder\ImportConfig.xml

    Write-Host "Updating Build.yaml ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\build.yaml) -replace "replaceRepo", $adoRepo | Set-Content -Path \Dev\Repos\$adoRepo\build.yaml
    (Get-Content -Path \Dev\Repos\$adoRepo\build.yaml) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\build.yaml

    Write-Host "Updating XrmContext.exe.config ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\XrmContext\XrmContext.exe.config) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\XrmContext\XrmContext.exe.config

    Write-Host "Updating XrmDefinitelyTyped.exe.config ..."
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\XrmDefinitelyTyped\XrmDefinitelyTyped.exe.config) -replace "AddName", $chosenSolution | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\XrmDefinitelyTyped\XrmDefinitelyTyped.exe.config

    Write-Host "Updating Companion App Settings"
    (Get-Content -Path \Dev\Repos\$adoRepo\PortalCompanionApp\AppSettings.json) -replace "https://AddName.crm6.dynamics.com", $conn.ConnectedOrgPublishedEndpoints["WebApplication"] | Set-Content -Path \Dev\Repos\$adoRepo\PortalCompanionApp\AppSettings.json

    Write-Host "Updating Webhook Settings"
    (Get-Content -Path \Dev\Repos\$adoRepo\Webhook\local.settings.json) -replace "https://AddName.crm6.dynamics.com", $conn.ConnectedOrgPublishedEndpoints["WebApplication"] | Set-Content -Path \Dev\Repos\$adoRepo\Webhook\local.settings.json

    Write-Host "Rename PowerPlatformDevOps.sln to $adoRepo.sln"
    Rename-Item -Path \Dev\Repos\$adoRepo\PowerPlatformDevOps.sln -NewName "$adoRepo.sln"
    (Get-Content -Path \Dev\Repos\$adoRepo\Plugins\Plugins.csproj) -replace "PowerPlatformDevOpsPlugins", ($adoRepo + "Plugins") | Set-Content -Path \Dev\Repos\$adoRepo\Plugins\Plugins.csproj
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\map.xml) -replace "PowerPlatformDevOpsPlugins", ($adoRepo + "Plugins") | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\map.xml
    (Get-Content -Path \Dev\Repos\$adoRepo\Workflows\Workflows.csproj) -replace "PowerPlatformDevOpsWorkflows", ($adoRepo + "Workflows") | Set-Content -Path \Dev\Repos\$adoRepo\Workflows\Workflows.csproj
    (Get-Content -Path \Dev\Repos\$adoRepo\Solutions\map.xml) -replace "PowerPlatformDevOpsWorkflows", ($adoRepo + "Workflows") | Set-Content -Path \Dev\Repos\$adoRepo\Solutions\map.xml


    $message = "Connecting to Deployment Staging (CI/CD)"
    Write-Host $message
    $ProgressBar = New-BTProgressBar -Status $message -Value 0.85
    New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

    Write-Host ""
    Write-Host "---- Please Select your Deployment Staging (CI/CD) Environment ------"
    $connCICD = Connect-CrmOnlineDiscovery -Credential $Credentials
    #>

    # Not sure what this following line does or whetherr I need it...
    # & ".\\SolutionExport.ps1"
    
    #commit repo and update VariableGroup in DevOps

    git add -A
    git commit -m "Initial Commit"
    git push origin master --force

    <#

    $message = "Creating variable groups in Azure DevOps"
    Write-Host $message
    $ProgressBar = New-BTProgressBar -Status $message -Value 0.90
    New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

    $varGroup = az pipelines variable-group create --name "$adoRepo.D365DevEnvironment"  --variables d365username=$username --authorize $true | ConvertFrom-Json
    az pipelines variable-group variable create --name d365password --value $password --secret $true --group-id $varGroup.id
    az pipelines variable-group variable create --name d365url --value $conn.ConnectedOrgPublishedEndpoints["WebApplication"]  --group-id $varGroup.id

    $varGroupCICD = az pipelines variable-group create --name "$adoRepo.D365CDEnvironment"  --variables d365username=$username --authorize $true | ConvertFrom-Json
    az pipelines variable-group variable create --name d365password --value $password --secret $true --group-id $varGroupCICD.id
    az pipelines variable-group variable create --name aadTenant --value $adAppCreds.tenant --group-id $varGroupCICD.id
    az pipelines variable-group variable create --name aadPowerAppId --value $adAppCreds.appId --group-id $varGroupCICD.id
    az pipelines variable-group variable create --name aadPowerAppSecret --value $adAppCreds.password --secret $true --group-id $varGroupCICD.id
    az pipelines variable-group variable create --name d365url --value $connCICD.ConnectedOrgPublishedEndpoints["WebApplication"]  --group-id $varGroupCICD.id

    $message = "Creating Build and Deploy Pipeline in Azure DevOps"
    Write-Host $message
    $ProgressBar = New-BTProgressBar -Status $message -Value 0.95
    New-BurntToastNotification -Text $Text -ProgressBar $ProgressBar -Silent -UniqueIdentifier $UniqueId

    $pipeline = az pipelines create --name "$adoRepo.CI" --yml-path /build.yaml --repository $adoRepo --repository-type tfsgit --branch master | ConvertFrom-Json

    az repos show --repository $repo.id --open
    az pipelines show --id $pipeline.definition.id --open

    #Provision Azure Resource group 
    Write-Host "Setting up the Azure Resource group requires both Azure and your Power Platform/Dynamics 365 to be on the same Azure AD Tenant"
    $AzureSetup = Read-Host -Prompt "Azure subscriptions : Would you like to create the default Azure resources [Y] Yes or [S] Skip (Default [S])"

    if ($AzureSetup -eq "Y") {
    
        $selection = az login | Out-String | ConvertFrom-Json
        $choiceIndex = 0
        $selection | ForEach-Object { write-host "[$($choiceIndex)] $($_.Name)"; $choiceIndex++; }     
        $subscriptionName = $null 
        $success = $false

        do {
            $choice = read-host "Select the Azure Subscription you want to deploy to"
            if (!$choice) {
                Write-Host "Invalid selection (null)"
            }
            else {
                $choice = $choice -as [int];
                if ($choice -eq $null) {
                    Write-Host "Invalid selection (not number)"
                }
                elseif ($choice -le -1) {
                    Write-Host "Invalid selection (negative)"
                }
                else {
                    $subscriptionId = $selection[$choice].id
                    $subscriptionName = $selection[$choice].name
                    if ($null -ne $subscriptionName) {
                        Write-Host "Selected Subscription : $subscriptionName"
                        $success = $true
                    }
                    else {
                        Write-Host "Invalid selection (index out of range)"
                    }
                } 
            }
        } while (!$success)

        az account set --subscription $subscriptionId

        $selection = az account list-locations --output json | Out-String | ConvertFrom-Json
        $choiceIndex = 0
        $selection | ForEach-Object { write-host "[$($choiceIndex)] $($_.name)"; $choiceIndex++; } 
        $regionName = $null 
        $success = $false

        do {
            $choice = read-host "Select the Azure Region you want to deploy to"
            if (!$choice) {
                Write-Host "Invalid selection (null)"
            }
            else {
                $choice = $choice -as [int];
                if ($choice -eq $null) {
                    Write-Host "Invalid selection (not number)"
                }
                elseif ($choice -le -1) {
                    Write-Host "Invalid selection (negative)"
                }
                else {
                    $regionName = $selection[$choice].name
                    if ($null -ne $regionName) {
                        Write-Host "Selected Region : $regionName"
                        $success = $true
                    }
                    else {
                        Write-Host "Invalid selection (index out of range)"
                    }
                } 
            }
        } while (!$success)



        Write-Host "Updating ARM Parameter values"
        $adoRepoLower = $adoRepo.ToLower()
        (Get-Content -Path \Dev\Repos\$adoRepo\AzureResources\azuredeploy.parameters.json) -replace "AddName" , $adoRepoLower | Set-Content -Path \Dev\Repos\$adoRepo\AzureResources\azuredeploy.parameters.json
        (Get-Content -Path \Dev\Repos\$adoRepo\AzureResources\azuredeploy.parameters.json) -replace "AddGeography" , $regionName.ToLower() | Set-Content -Path \Dev\Repos\$adoRepo\AzureResources\azuredeploy.parameters.json

        Write-Host "Set new variables in Azure DevOps"
        az pipelines variable-group variable create --name CompanionAppName --value "$adoRepoLower-wba" --group-id $varGroup.id
        az pipelines variable-group variable create --name WebhookAppName --value "$adoRepoLower-fna" --group-id $varGroup.id
        az pipelines variable-group variable create --name d365AppSecurityRoleNames --value "Delegate" --group-id $varGroup.id

        az pipelines variable-group variable create --name CompanionAppName --value "$adoRepoLower-wba" --group-id $varGroupCICD.id
        az pipelines variable-group variable create --name WebhookAppName --value "$adoRepoLower-fna" --group-id $varGroupCICD.id
        az pipelines variable-group variable create --name d365AppSecurityRoleNames --value "Delegate" --group-id $varGroupCICD.id


        chdir -Path C:\Dev\Repos\$adoRepo\AzureResources\
        & .\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation $regionName -ResourceGroupName "$adoRepoLower-dev"
    }
    #>

    Write-Host
    WriteProgressMessage("Complete ... Enjoy !!!")

    # Launch the new Workspace in VS Code
    code "$FullLocalRepoPath\$WorkspaceName.code-workspace"

}


$message = @"
   ____     ____       ____  U _____ u__     __    U  ___ u  ____     ____     
U | __")uU /"___|     |  _"\ \| ___"|/\ \   /"/u    \/"_ \/U|  _"\ u / __"| u  
 \|  _ \/\| | u      /| | | | |  _|"   \ \ / //     | | | |\| |_) |/<\___ \/   
  | |_) | | |/__     U| |_| |\| |___   /\ V /_,-.-,_| |_| | |  __/   u___) |   
  |____/   \____|     |____/ u|_____| U  \_/-(_/ \_)-\___/  |_|      |____/>>  
 _|| \\_  _// \\       |||_   <<   >>   //            \\    ||>>_     )(  (__) 
(__) (__)(__)(__)     (__)_) (__) (__) (__)          (__)  (__)__)   (__)      


Welcome to the Business Central DevOps provisioning script. This script will perform the following steps automatically:

 - Use -InstallPreReqs = \$true to install chocolatey, git, and Azure CLI
 - Connect to Azure DevOps (You will need to have an Azure DevOps organisation to use, if you don't have one, please create one at https://dev.azure.com)
 - Allow you to Create a New Project in Azure DevOps or to Select an existing one
 - Create a New Git Repository in the Project to store your Source Code
 - Clone a BC Template Repository into your new Azure DevOps repository
 - Clone your new repository locally to <root>\Dev\Repos
 - Update your new app with a new app id and name 
 - Commit Solution to Source Control and sync to your Azure DevOps repo
 - Open VS Code on your new workspace

 to come later...

 - Create an Azure DevOps Multi-Stage Pipeline to Build and Continuously Deploy your Code and Solutions
 - Create Variable Groups in Azure DevOps with your Power Platform details and credentials (stored as secrets)
 - Open the Repo and Pipeline in the Browser (and complete the initial Build and Deploy)       
 - Create new Azure ResourceGroup in your selected Azure Subscription



"@

$bckgrnd = $Host.UI.RawUI.BackgroundColor
Clear-Host
Write-Host $message

$quit = Read-Host -Prompt "Press Enter to Continue or [Q]uit"
if ($quit -eq "Q") {
    exit
}

# Get the YellowChook repos
$YellowChookRepos = Invoke-WebRequest "api.github.com/users/YellowChook/repos"
$ReposJson = $YellowChookRepos.Content | ConvertFrom-Json
$BCVersionsAvailable = $ReposJson | Where-Object { ($_.Name -Match "^BC.*") }
if ($BCVersion -notin $BCVersionsAvailable.Name) {
    if ($BCVersionsAvailable.Length -eq 1) {
        $BCVersion = $BCVersionsAvailable.Name
    } 
    else {
        $selection = $BCVersionsAvailable | Select-Object Name 
        $choiceIndex = 0
        $options = $selection | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription "&$($choiceIndex) - $($_.Name)"; $choiceIndex++ }
        $chosenIndex = $host.ui.PromptForChoice("BC Version", "Select the Version you wish to use", $options, $BCVersionsAvailable.Length - 1)
        $BCVersion = $selection[$chosenIndex].Name 
    }    
}
WriteProgressMessage("Creating new repo for $BCVersion")

if ($InstallPreReqs) {
    Write-Host("Performing Checks....")

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-PowerAppsAdmin
    Install-PreRequisites
}

DevOps-Install
