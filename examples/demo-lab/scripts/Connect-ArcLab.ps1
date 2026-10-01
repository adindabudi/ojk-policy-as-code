#Requires -Version 7.0
<#
.SYNOPSIS
  Connects the lab's Windows Server VMs to Azure Arc so they behave like on-premises servers.

.DESCRIPTION
  Lab only. Follows "Evaluate Azure Arc-enabled servers on an Azure virtual machine"
  (https://learn.microsoft.com/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine):
    1. remove VM extensions and set MSFT_ARC_TEST, then reboot so services see the variable
    2. block the Azure IMDS endpoints, install the Connected Machine agent and connect it
    3. disable the Azure VM guest agent a few minutes later (after the run command has reported back)
    4. set periodic update assessment on the Arc-enabled servers and, where Azure Update Manager
       supports Arc-enabled servers in the region, start an assessment (and optional patching)
  Authentication uses short-lived access tokens from the current Azure CLI session, always for the
  subscription given here, so a different default subscription in Azure CLI does not matter.
  For real on-premises servers use a dedicated onboarding service principal and, for banks,
  an Azure Arc Private Link Scope over ExpressRoute or VPN.

  Azure Update Manager lists the regions that support Arc-enabled servers
  (https://learn.microsoft.com/azure/update-manager/supported-regions). Where on-demand assessment is not
  available, the script still sets periodic assessment and skips the on-demand assessment and patching calls.

.EXAMPLE
  ./Connect-ArcLab.ps1 -SubscriptionId <id> -SimResourceGroup rg-ojkdemo-onprem-sim -ArcResourceGroup rg-ojkdemo-idc -Location indonesiacentral
  ./Connect-ArcLab.ps1 -SubscriptionId <id> -SimResourceGroup rg-ojkdemo-onprem-sim -ArcResourceGroup rg-ojkdemo-idc -Location indonesiacentral -SkipOnboarding
#>
[CmdletBinding()]
param(
  [string]   $SubscriptionId,
  [Parameter(Mandatory)] [string] $SimResourceGroup,
  [Parameter(Mandatory)] [string] $ArcResourceGroup,
  [Parameter(Mandatory)] [string] $Location,
  [string[]] $Servers,
  [string[]] $PatchServers = @(),
  [switch]   $SkipOnboarding,
  [string]   $ArcApiVersion = '2024-07-10'
)

$ErrorActionPreference = 'Stop'

function Invoke-Az {
  $out = & az @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed:`n$out" }
  return $out
}

function Invoke-Arm([string]$Method, [string]$Url, [string]$Body) {
  $token = (Invoke-Az account get-access-token --subscription $SubscriptionId --resource https://management.azure.com/ --query accessToken -o tsv).Trim()
  $params = @{ Method = $Method; Uri = $Url; Headers = @{ Authorization = "Bearer $token" }; ContentType = 'application/json' }
  if ($Body) { $params.Body = $Body }
  Invoke-RestMethod @params
}

if (-not $SubscriptionId) { $SubscriptionId = (Invoke-Az account show --query id -o tsv).Trim() }
$tenantId = (Invoke-Az account show --subscription $SubscriptionId --query tenantId -o tsv).Trim()
if (-not $Servers) {
  $Servers = (Invoke-Az vm list -g $SimResourceGroup --subscription $SubscriptionId --query "[].name" -o tsv) -split "`r?`n" | Where-Object { $_ }
}
Write-Host "Subscription: $SubscriptionId  Servers: $($Servers -join ', ')"

$prepareScript = @'
[Environment]::SetEnvironmentVariable('MSFT_ARC_TEST', 'true', [EnvironmentVariableTarget]::Machine)
shutdown.exe /r /t 30 /c "Arc lab: reboot so services pick up MSFT_ARC_TEST" /d p:4:1
'MSFT_ARC_TEST set; reboot in 30 seconds'
'@

$connectScript = @'
param([string]$SubscriptionId, [string]$TenantId, [string]$ResourceGroup, [string]$Location, [string]$Token)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Only the Arc IMDS (localhost) should answer identity and metadata requests.
foreach ($ip in '169.254.169.254', '169.254.169.253') {
  $name = "Block Azure IMDS $ip"
  if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $name -Direction Outbound -Action Block -RemoteAddress $ip -Profile Any | Out-Null
  }
}

$msi = Join-Path $env:TEMP 'AzureConnectedMachineAgent.msi'
Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/AzureConnectedMachineAgent' -OutFile $msi
$p = Start-Process msiexec.exe -ArgumentList '/i', $msi, '/qn', '/l*v', (Join-Path $env:TEMP 'azcmagent-install.log') -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Agent install failed with exit code $($p.ExitCode)" }

$azcmagent = Join-Path $env:ProgramW6432 'AzureConnectedMachineAgent\azcmagent.exe'
& $azcmagent connect --subscription-id $SubscriptionId --tenant-id $TenantId --resource-group $ResourceGroup `
  --location $Location --access-token $Token --tags 'environment=demo-lab,site=onprem-simulated' --cloud AzureCloud
if ($LASTEXITCODE -ne 0) { throw "azcmagent connect failed with exit code $LASTEXITCODE" }

# Disable the Azure VM guest agent after this run command has reported its result.
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "Set-Service WindowsAzureGuestAgent -StartupType Disabled; Stop-Service WindowsAzureGuestAgent -Force"'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(3)
Register-ScheduledTask -TaskName 'ArcLab-DisableAzureGuestAgent' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null

& $azcmagent show
'@

function Wait-GuestAgentReady([string]$vm) {
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 15
    $status = Invoke-Az vm get-instance-view -g $SimResourceGroup -n $vm --subscription $SubscriptionId `
      --query "instanceView.vmAgent.statuses[0].displayStatus" -o tsv 2>$null
    if ($status -eq 'Ready') { return }
  }
  throw "Guest agent on $vm did not become ready"
}

# 1. Remove VM extensions, set MSFT_ARC_TEST and reboot.
if (-not $SkipOnboarding) {
  foreach ($vm in $Servers) {
    $exts = (Invoke-Az vm extension list -g $SimResourceGroup --vm-name $vm --subscription $SubscriptionId --query "[].name" -o tsv) -split "`r?`n" | Where-Object { $_ }
    foreach ($ext in $exts) {
      Write-Host "[$vm] removing VM extension $ext"
      Invoke-Az vm extension delete -g $SimResourceGroup --vm-name $vm -n $ext --subscription $SubscriptionId | Out-Null
    }
    Write-Host "[$vm] setting MSFT_ARC_TEST and rebooting"
    Invoke-Az vm run-command invoke -g $SimResourceGroup -n $vm --subscription $SubscriptionId `
      --command-id RunPowerShellScript --scripts $prepareScript --query "value[0].message" -o tsv | Write-Host
  }
  Start-Sleep -Seconds 60
  foreach ($vm in $Servers) { Wait-GuestAgentReady $vm; Write-Host "[$vm] back online" }

  # 2. Install the Connected Machine agent and connect.
  $scriptFile = New-TemporaryFile
  Set-Content -Path $scriptFile -Value $connectScript -Encoding utf8
  try {
    foreach ($vm in $Servers) {
      $token = (Invoke-Az account get-access-token --subscription $SubscriptionId --resource https://management.azure.com/ --query accessToken -o tsv).Trim()
      Write-Host "[$vm] installing the agent and connecting to $ArcResourceGroup ($Location)"
      Invoke-Az vm run-command invoke -g $SimResourceGroup -n $vm --subscription $SubscriptionId `
        --command-id RunPowerShellScript --scripts "@$scriptFile" `
        --parameters "SubscriptionId=$SubscriptionId" "TenantId=$tenantId" "ResourceGroup=$ArcResourceGroup" "Location=$Location" "Token=$token" `
        --query "value[].message" -o tsv | Write-Host
    }
  }
  finally {
    Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
  }
}

# 3. Periodic update assessment, first assessment and optional patching through Azure Update Manager.
$base = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ArcResourceGroup/providers/Microsoft.HybridCompute/machines"
$patchBody = '{"properties":{"osProfile":{"windowsConfiguration":{"patchSettings":{"assessmentMode":"AutomaticByPlatform"}}}}}'
$updateManagerAvailable = $true

foreach ($vm in $Servers) {
  $state = $null
  for ($i = 0; $i -lt 20; $i++) {
    $state = (Invoke-Arm GET "$base/$($vm)?api-version=$ArcApiVersion").properties.status
    if ($state -eq 'Connected') { break }
    Start-Sleep -Seconds 15
  }
  Write-Host "[$vm] Arc status: $state; setting periodic assessment"
  Invoke-Arm PATCH "$base/$($vm)?api-version=$ArcApiVersion" $patchBody | Out-Null

  if ($updateManagerAvailable) {
    try {
      Invoke-Arm POST "$base/$vm/assessPatches?api-version=$ArcApiVersion" | Out-Null
      Write-Host "[$vm] update assessment started"
    }
    catch {
      if ($_.ErrorDetails.Message -match 'RegionNotEnabled') {
        $updateManagerAvailable = $false
        Write-Warning "On-demand assessment and patching through Azure Update Manager are not available for Arc-enabled servers in '$Location' yet. Periodic assessment is set, and results usually appear within an hour. See https://learn.microsoft.com/azure/update-manager/supported-regions"
      }
      else { throw }
    }
  }
}

if ($updateManagerAvailable) {
  $installBody = '{"maximumDuration":"PT2H","rebootSetting":"IfRequired","windowsParameters":{"classificationsToInclude":["Critical","Security","UpdateRollup","Updates","Definition"]}}'
  foreach ($vm in $PatchServers) {
    Invoke-Arm POST "$base/$vm/installPatches?api-version=$ArcApiVersion" $installBody | Out-Null
    Write-Host "[$vm] update installation started (up to 2 hours, reboots if required)"
  }
}

Write-Host "Done. Trigger a policy scan:"
Write-Host "  az policy state trigger-scan --resource-group $ArcResourceGroup --subscription $SubscriptionId --no-wait"
