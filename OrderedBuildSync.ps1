<# Common PowerShell functions used by the Dynamics AX 7.0 build process. #>

<#
.SYNOPSIS
    Build and sync local environment using ordered models list.
    
.DESCRIPTION
    This script builds models in a certain order to avoid a known issue
    in Dynamics 365 FO. Sometimes it does not consider the dependencies between them.

.NOTES
    When running through automation, set the $LogPath variable to redirect
    all output to a log file rather than the console. Can be set in calling script.   
    
    Disclaimer:  
    This code is made available AS IS and is not supported.
    The risk of the use or the results from the use of this code remains with the user.

    Most of the functions has been directly copied from .../DynamicsSDK/DynamicsSDKCommon.ps1.
#>

function Get-AX7DeploymentAosWebConfigPath
{
    [Cmdletbinding()]
    Param([string]$WebsiteName)
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    [string]$AosWebConfigPath = $null

    [string]$AosWebsitePath = Get-AX7DeploymentAosWebsitePath -WebsiteName $WebsiteName

    if ($AosWebsitePath)
    {
        $AosWebConfigPath = Join-Path -Path $AosWebsitePath -ChildPath "web.config"
    }

    return $AosWebConfigPath
}

function Get-AX7DeploymentAosWebsitePath
{
    [Cmdletbinding()]
    Param([string]$WebsiteName)
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    [string]$AosWebsitePath = $null

    # Get website and its physical path.
    $Website = Get-AX7DeploymentAosWebsite -WebsiteName $WebsiteName
    if ($Website)
    {
        $AosWebsitePath = $Website.physicalPath
    }
    else
    {
        throw "No AOS website could be found in IIS."
    }

    return $AosWebsitePath
}

function Get-AX7DeploymentAosWebsite
{
    [Cmdletbinding()]
    Param([string]$WebsiteName)
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    # Import only the functions needed (Too noisy with Verbose).
    Import-Module -Name "WebAdministration" -Function "Get-Website" -Verbose:$false

    [Microsoft.IIs.PowerShell.Framework.ConfigurationElement]$Website = $null

    if ($WebsiteName)
    {
        # Use specified website name.
        $Website = Get-Website -Name $WebsiteName
    }
    else
    {
        # Try default service model website name.
        $Website = Get-Website -Name "AosService"
        if (!$Website)
        {
            # Try default deploy website name.
            $Website = Get-Website -Name "AosWebApplication"
        }
    }

    return $Website
}

function Restart-IIS
{
    [Cmdletbinding()]
    Param()
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    Write-Message "- Calling IISReset /RESTART to restart IIS..." -Diag
    
    $IISResetOutput = & IISReset /RESTART
    
    # Check exit code to make sure the service was correctly removed.
    $IISResetExitCode = [int]$LASTEXITCODE
    
    # Log output if any.
    if ($IISResetOutput -and $IISResetOutput.Count -gt 0)
    {
        $IISResetOutput | % { Write-Message $_ -Diag }
    }

    Write-Message "- IISReset completed with exit code: $IISResetExitCode" -Diag
    if ($IISResetExitCode -ne 0)
	{
		throw "IISReset returned an unexpected exit code: $IISResetExitCode"
	}

    Write-Message "- IIS restarted successfully." -Diag
}

function Write-Message
{
    [Cmdletbinding()]
    Param([string]$Message, [switch]$Error, [switch]$Warning, [switch]$Diag, [string]$LogPath = $PSCmdlet.GetVariableValue("LogPath"))

    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    if ($LogPath)
    {
        # For log files use full UTC time stamp.
        "$([DateTime]::UtcNow.ToString("s")): $($Message)" | Out-File -FilePath $LogPath -Append
    }
    else
    {
        # For writing to host use a local time stamp.
        [string]$FormattedMessage = "$([DateTime]::Now.ToLongTimeString()): $($Message)"
        
        # If message is of type Error, use Write-Error.
        if ($Error)
        {
            Write-Error $FormattedMessage
        }
        else
        {
            # If message is of type Warning, use Write-Warning.
            if ($Warning)
            {
                Write-Warning $FormattedMessage
            }
            else
            {
                # If message is of type Verbose, use Write-Verbose.
                if ($Diag)
                {
                    Write-Verbose $FormattedMessage
                }
                else
                {
                    Write-Host $FormattedMessage
                }
            }
        }
    }
}

function Get-AX7DeploymentAosWebConfigSetting
{
    [Cmdletbinding()]
    Param([string]$WebConfigPath, [string]$Name)
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")

    [string]$SettingValue = $null

    if (Test-Path -Path $WebConfigPath -PathType Leaf)
    {
        [xml]$WebConfig = Get-Content -Path $WebConfigPath
        if ($WebConfig)
        {
            $XPath = "/configuration/appSettings/add[@key='$($Name)']"
            $KeyNode = $WebConfig.SelectSingleNode($XPath)
            if ($KeyNode)
            {
                $SettingValue = $KeyNode.Value
            }
            else
            {
                throw "Failed to find setting in web.config at: $XPath"
            }
        }
        else
        {
            throw "Failed to read web.config content from: $WebConfigPath"
        }
    }
    else
    {
        throw "The specified web.config file could not be found at: $WebConfigPath"
    }

    return $SettingValue
}

function Get-AX7DeploymentPackagesPath
{
    [Cmdletbinding()]
    Param([string]$WebConfigPath)
    
    # Get verbose preference from caller.
    $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference")
        
    [string]$PackagesPath = $null

    if (!$WebConfigPath)
    {
        $WebConfigPath = Get-AX7DeploymentAosWebConfigPath
    }
    $PackagesPath = Get-AX7DeploymentAosWebConfigSetting -WebConfigPath $WebConfigPath -Name "Aos.PackageDirectory"

    return $PackagesPath
}

[int]$ExitCode = 0
try 
{
    $models = (
        "ApplicationFoundation",
        "Currency",
        "Directory",
        "PersonnelManagement",
        "CaseManagement",
        "Policy",
        "ApplicationSuite",
        "MyNewModule" # Insert your models here!!!
    )

    $RegPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\AX\7.0\SDK"
    $RegKey = Get-ItemProperty -Path $RegPath
    $AosWebsiteName = "AOSService"

    if ($AosWebsiteName)
    {
        Write-Message "- Setting AosWebsiteName registry value: $AosWebsiteName" -Diag
        New-ItemProperty -Path $RegPath -Name "AosWebsiteName" -Value $AosWebsiteName -Force
    }
    
    $RegKey = Get-ItemProperty -Path $RegPath
    $WebConfigPath = Get-AX7DeploymentAosWebConfigPath -WebsiteName $RegKey.AosWebsiteName
    $PackagesPath = Get-AX7DeploymentPackagesPath -WebConfigPath $WebConfigPath
    $XppcPath = "$($PackagesPath)\bin\xppc.exe"
    $SyncEnginePath = "$($PackagesPath)\bin\SyncEngine.exe"

    Write-Progress -Id 1 -Activity "BUILD AND SYNC"

    $NewGuid = [System.Guid]::NewGuid().ToString()
    $NewDir = "$env:TEMP\$NewGuid"

    # Create new temp folder
    New-Item -ItemType directory -Path $NewDir
    
    # Build models in order
    [int]$Counter = 1
    Foreach ($model in $models)
    {
        Write-Progress -ParentId 1 -Activity "Building $model model..." -PercentComplete ($Counter / $models.Count * 100)       
        & $XppcPath "-verbose" "-failfast" "-modelmodule=$($model)" "-metadata=$($PackagesPath)" "-output=$($PackagesPath)\$($model)\bin" "-xref" "-referenceFolder=$($PackagesPath)" "-refPath=$($PackagesPath)\$($model)\bin" "-xmllog=$NewDir\$model.xml" "-log=$NewDir\$model.log"

        $Counter = $Counter + 1
    }

    # Restart IIS
    Restart-IIS

    # Sync database 
    & $SyncEnginePath "-syncmode=fullall" "-metadatabinaries=$($PackagesPath)" '-connect="Data Source=localhost;Initial Catalog=AxDB;Integrated Security=True;Enlist=True;Application Name=SyncEngine"' "-fallbacktonative=False" "-verbosity=Normal"

    # Open folder with log files 
    explorer.exe $NewDir
}
catch [System.Exception]
{
    Write-Message "- Exception thrown at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())$([Environment]::NewLine)$($_.Exception.ToString())" -Diag
    Write-Message "Error executing script: $($_)" -Error
    $ExitCode = -1
}

Write-Message "Script completed with exit code: $ExitCode"
Exit $ExitCode
