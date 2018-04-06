<#     
.SYNOPSIS     
   Script used to provision users to use Dynamics 365 for Operations Developer Tools.  
     
.DESCRIPTION   
   Script used to provision users to use Dynamics 365 for Operations Developer Tools. The current user must be part of the Administrators group to run this script as well to use
   Dynamics 365 for Operations Developer tools. This script creates SQL Server logins for the users provided as arguments and creates corresponding users for Dynamics Xref
   database.
      
.NOTES     
    Name: ProvisionAxDeveloper
    Author: Microsoft
    DateCreated: 11Jan2016
      
.EXAMPLE     
    ProvisionAxDeveloper.ps1 <dbServerName> <domain or hostname\user1>,<domain or hostname\user2>,<domain or hostname\user3>...
      
   
Description   
-----------       
The user who runs this command must be an administrator. On running this command we will check if the users given in the arguments
are part of administrators group. If the check passes we will go provision the Dynamics 365 for Operations Developer Tools for all provided users. If any
of the users are not part of administrators group we will fail the script in the validation phase itself.

Disclaimer:  
This code is made available AS IS and is not supported by Microsoft.
The risk of the use or the results from the use of this code remains with the user.
#>  
[cmdletbinding()]
Param(
    [Parameter(Mandatory=$True)]
    [string] $databaseServerName,
    [Parameter(Mandatory=$True)]
    [string[]] $users
    )
    
$AdminUsers = {}

#
# Check if the current user has admin privileges. User must be an administrator or part of builtin\administrators group
#
Try 
{
    $AdminUsers = invoke-command {   net localgroup administrators | where {$_ -AND $_ -notmatch "command completed successfully"} |  select -skip 4 }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
    If(($principal.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator ) -eq $false) -AND ($AdminUsers -contains $userName -eq $false )) 
    {
        Write-Host "You must be an administrator to run this script"
        return -1
    }
} 
Catch 
{
    $ErrorRecord = $Error[0]
    $ErrorRecord | Format-List * -Force
    $ErrorRecord.InvocationInfo |Format-List *
    $Exception = $ErrorRecord.Exception

    For ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
    {   "$i" * 80
        $Exception |Format-List * -Force
    }
    Throw "Failed to determine if the current user has elevated privileges. The error was: '{0}'." -f $_
}

If($PSBoundParameters.Count -lt 1)
{
    Write-Host "Usage: \n PrepareAxTools.ps1 <user1>,<user2>,<user3>...\n Users must be part of Administrators group"
    return -1
}

$AdminUsers = Invoke-command {   net localgroup administrators | where {$_ -AND $_ -notmatch "command completed successfully"} |  select -skip 4 }

#
# Validate if the user[s] argument are part of Administrators group
#

#Begin Validation
$quit = $false

Foreach ($user in $users)
{
    $userNameComponents = $user.Split('\')
    $username = ''
    $domain = ''
        
    If($userNameComponents.Count -eq 2)
    {
        $domain = $userNameComponents[0]
        $username = $userNameComponents[1]

        #
        # For the local user accounts, windows does not store the Computer Name in the administrators user group.
        #
        If($domain -eq $env:computername) 
        {
            $user = $username
        }
    }
    Else
    {
        Write-Host "Invalid format. User name must be of format 'domain or hostname\username'"
        return -1
    }

    If(-NOT ($AdminUsers -contains $user))
    {   
        Write-Host $user "is not part of Administrators group."
        $quit = $true       
    }
}

If($quit -eq $true) 
{
    Write-Host "Users must be part of Administrators group. Please add the user[s] to the builtin\Administrators group and re-run the script"
    return -1
}
#End Validation

#
# Provision SQL access to the users
#
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | out-null
$databaseServerName = $env:databaseServerName
$ManagedComputer = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $databaseServerName

$serverInstance = ""


#
# Provision user access
#

#Begin Provision
Foreach($user in $users) 
{
    Try
    {

        $sqlSrv = New-Object 'Microsoft.SqlServer.Management.Smo.Server' "$databaseServerName"
	
        $login = $sqlSrv.Logins.Item($user)
        $dbName = "DYNAMICSXREFDB"
        $database = $sqlSrv.Databases[$dbName]
        $dbRoleName = "db_owner"
        $dbRole = $database.Roles[$dbRoleName]

        If(-Not ($login)) 
        {
            $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $sqlSrv, $user
            $login.LoginType = "WindowsUser"
            $login.Create()
    
        }
        else 
        {
            Write-Host "User $user already exists"
        }
        
        If(-Not ($login.IsMember("sysadmin"))) 
        {
            $login.AddToRole("sysadmin")
            $login.Alter()
            $sqlSrv.Refresh()
        }
        else 
        {
            Write-Host "User $user is already a member of sysadmin"
        }
        
        If(-Not $database.Users[$user] )
        {
            #
            # Map the user to database 
            #
            $sql = "CREATE USER `"$user`" FOR LOGIN `"$user`" WITH DEFAULT_SCHEMA=[dbo];
            EXEC sp_addrolemember 'db_owner', `"$user`""
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
            $sqlConnection.ConnectionString = "server=$databaseServerName;integrated security=TRUE;database=$dbName" 
            $sqlConnection.Open()
            $sqlCommand = new-object System.Data.SqlClient.SqlCommand
            $sqlCommand.CommandTimeout = 120
            $sqlCommand.Connection = $sqlConnection
            $sqlCommand.CommandText= $sql
            $text = $sql.Substring(0, 50)
            Write-Progress -Activity "Executing SQL" -Status "Executing SQL => $text..."
            Write-Host "Executing SQL => $text..."
            $result = $sqlCommand.ExecuteNonQuery()
            $sqlConnection.Close()
        }
        else 
        {
            Write-Host "User $user is already mapped to database $database"
        }
    }
    Catch 
    {
        $ErrorRecord = $Error[0]
        $ErrorRecord | Format-List * -Force
        $ErrorRecord.InvocationInfo |Format-List *
        $Exception = $ErrorRecord.Exception

        for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
        {   "$i" * 80
            $Exception |Format-List * -Force
        }

        Throw "Failed to provision database access for the user: $user"
    }  
}
#End Provision
