#
# xAzureCluster: DSC resource to configure a Failover Cluster consisting of Windows Azure VMs.
#

#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    param
    (	
        [parameter(Mandatory)]
        [string] $FarmAdmin,

        [parameter(Mandatory)]
        [string] $FarmAdminPassword,

        [parameter(Mandatory)]
        [string] $FarmPassphrase,

        [parameter(Mandatory)]
        [string] $DbServer,

        [parameter(Mandatory)]
        [string] $ConfigurationDbName,

        [parameter(Mandatory)]
        [string] $CAContentDbName,

        [parameter(Mandatory)]
        [string] $LogLocation,

        [parameter(Mandatory)]
        [Uint32] $LogDiskSpaceUsageGB,			
        
        [parameter(Mandatory)]
        [PSCredential] $SqlAdministratorCredential
    )       

    $retvalue = @{
        DbServer = $DbServer;
        ConfigurationDbName = $ConfigurationDbName;
        CAContentDbName = $CAContentDbName;
    }
}

#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
    param
    (        
        [parameter(Mandatory)]
        [string] $FarmAdmin,

        [parameter(Mandatory)]
        [string] $FarmAdminPassword,

        [parameter(Mandatory)]
        [string] $FarmPassphrase,

        [parameter(Mandatory)]
        [string] $DbServer,

        [parameter(Mandatory)]
        [string] $ConfigurationDbName,

        [parameter(Mandatory)]
        [string] $CAContentDbName,

        [parameter(Mandatory)]
        [string] $LogLocation,

        [parameter(Mandatory)]
        [Uint32] $LogDiskSpaceUsageGB,
        
        [parameter(Mandatory)]
        [PSCredential] $SqlAdministratorCredential
    )       
	
    $FarmAdministratorCredential = New-Object PSCredential $FarmAdmin, (ConvertTo-SecureString $FarmAdminPassword -AsPlainText -Force)		
    try
    {		
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $FarmAdministratorCredential  
		
		Write-Verbose "Loading snapin.."
		Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
		
        # disable loopback to fix 401s from SP Webs Service calls
        New-ItemProperty HKLM:\System\CurrentControlSet\Control\Lsa -Name DisableLoopbackCheck -Value 1 -PropertyType dword -Force -ErrorAction Ignore | Out-Null

        CreateOrJoinFarm -FarmAdmin $FarmAdmin -FarmAdminPassword $FarmAdminPassword -FarmPassphrase $FarmPassphrase `
                         -DbServer $DbServer -ConfigurationDbName $ConfigurationDbName -CAContentDbName $CAContentDbName `
                         -SqlAdministratorCredential $SqlAdministratorCredential

        Write-Verbose "Configuring SharePoint..."
        
        ConfigureLogging -LogLocation $LogLocation -LogDiskSpaceUsageGB $LogDiskSpaceUsageGB
                
        ConfigureFarm

    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
		Write-Verbose "Removing snapin.."
		Remove-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
    }
}

# 
# Test-TargetResource
#

function Test-TargetResource  
{
    param
    (        
        [parameter(Mandatory)]
        [string] $FarmAdmin,

        [parameter(Mandatory)]
        [string] $FarmAdminPassword,

        [parameter(Mandatory)]
        [string] $FarmPassphrase,       

        [parameter(Mandatory)]
        [string] $DbServer,

        [parameter(Mandatory)]
        [string] $ConfigurationDbName,

        [parameter(Mandatory)]
        [string] $CAContentDbName,

        [parameter(Mandatory)]
        [string] $LogLocation,

        [parameter(Mandatory)]
        [Uint32] $LogDiskSpaceUsageGB,			
        
        [parameter(Mandatory)]
        [PSCredential] $SqlAdministratorCredential
    )

    # Set-TargetResource is idempotent
    return $false
}


function Get-ImpersonatetLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@ 
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig 

   return $script:ImpersonateLib
    
}

function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)
    
    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw "Can't Logon as User $cred.GetNetworkCredential().UserName."
    }
    $context, $userToken
}

function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw "Can't close token"
    }
}

function CreateOrJoinFarm(
    [Parameter(Mandatory)]
    [string]$DbServer, 
    [Parameter(Mandatory)]
    [string]$FarmPassphrase,
    [Parameter(Mandatory)]
    [string]$FarmAdmin,    
    [Parameter(Mandatory)]
    [string]$FarmAdminPassword,
    [Parameter(Mandatory)]
    [string]$ConfigurationDbName,
    [Parameter(Mandatory)]
    [string]$CAContentDbName,
    [parameter(Mandatory)]
    [PSCredential] $SqlAdministratorCredential
)
{    
    $farmCredential = New-Object PSCredential $FarmAdmin, (ConvertTo-SecureString $FarmAdminPassword -AsPlainText -Force)
	$secPhrase = ConvertTo-SecureString $FarmPassphrase -AsPlainText -Force

	# Look for an existing farm and join the farm if not already joined, or create a new farm
	Write-Verbose "Checking farm membership in [$ConfigurationDbName]..."
	$spFarm = $null
	Try { $spFarm = Get-SPFarm | where Name -eq $ConfigurationDbName -ErrorAction SilentlyContinue } Catch {}

	If (!$spFarm)
	{
		Write-Verbose "Attempting to join farm on [$ConfigurationDbName]..."
		Connect-SPConfigurationDatabase -DatabaseName $ConfigurationDbName -Passphrase $secPhrase -DatabaseServer $DbServer -DatabaseCredentials $SqlAdministratorCredential -ErrorAction SilentlyContinue
		If (!$?)
		{
			Write-Verbose "No existing farm found. Creating config database [$ConfigurationDbName]..."
			# Waiting a few seconds seems to help with the Connect-SPConfigurationDatabase barging in on the New-SPConfigurationDatabase command; not sure why...
			Start-Sleep 5
			New-SPConfigurationDatabase -DatabaseName $ConfigurationDbName -DatabaseServer $DbServer -DatabaseCredentials $SqlAdministratorCredential -AdministrationContentDatabaseName $CAContentDbName -Passphrase $secPhrase -FarmCredentials $farmCredential
			If (!$?) {Throw "Error creating new farm configuration database"}

			Write-Verbose "Created new farm on [$ConfigurationDbName]."
		}
		Else
		{
			Write-Verbose "Joined farm."
		}
	    }
	 Else
	 {
		 Write-Verbose "Already joined to farm on [$ConfigurationDbName]."
	 }
}

function ConfigureLogging(
    [Parameter(Mandatory)]
    [string]$LogLocation, 
    [Parameter(Mandatory)]
    [Uint32]$LogDiskSpaceUsageGB
)
{
    # Configure logging
    Write-Verbose "Setting log location [$LogLocation] and enabling EventLog Flood Protection"
    Set-SPLogLevel -TraceSeverity Monitorable
    Set-SPDiagnosticConfig -LogLocation $LogLocation -EventLogFloodProtectionEnabled
    if ($LogDiskSpaceUsageGB > 0)
    {
        Write-Verbose "Limiting log size to [$LogDiskSpaceUsageGB GB]"
        Set-SPDiagnosticConfig -LogMaxDiskSpaceUsageEnabled -LogDiskSpaceUsageGB $LogDiskSpaceUsageGB
    }
}

function ConfigureFarm()
{    
    If(Test-Path "$env:TEMP\FarmConfigured.txt")
    {
        return
    }

    # Install help collections
    Write-Verbose "Install help collections..."
    Install-SPHelpCollection -All
                
    # Secure the SharePoint resources
    Write-Verbose "Securing SharePoint resources..."
    Initialize-SPResourceSecurity
                    
    # Install services
    Write-Verbose "Installing services..."
    Install-SPService
                    
    # Register SharePoint features
    Write-Verbose "Registering SharePoint features..."
    Install-SPFeature -AllExistingFeatures -Force | Out-Null

    # Install application content files
    Write-Verbose "Installing application content files..."
    Install-SPApplicationContent

    # Let's make sure the SharePoint Timer Service (SPTimerV4) is running
    # Per workaround in http://www.paulgrimley.com/2010/11/side-effects-of-attaching-additional.html
    $timersvc = Get-Service SPTimerV4
    If ($timersvc.Status -eq "Stopped")
    {
        Write-Verbose "Starting $($timersvc.DisplayName) service..."
        Start-Service $timersvc
        If (!$?) {Throw "Could not start $($timersvc.DisplayName) service!"}
    }

    New-Item -ItemType File -Path "$env:TEMP\FarmConfigured.txt" -Value "SharePoint configuration complete.." -Force
}
