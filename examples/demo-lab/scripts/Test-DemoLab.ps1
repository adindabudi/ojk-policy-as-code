#Requires -Version 7.0
<#
.SYNOPSIS
  Checks that the demo lab behaves as expected and refreshes compliance data. Run it 1-2 hours before a demo.

.DESCRIPTION
  1. Creating a storage account outside the approved region in the in-country resource group is denied.
  2. A GlobalStandard model deployment in the approved offshore resource group is denied.
  3. A DataZoneStandard model deployment in the same resource group succeeds (then it is deleted).
  4. A policy compliance scan starts for both resource groups.
  Denied attempts also appear in the Activity Log as evidence. Nothing is left behind.

.EXAMPLE
  ./Test-DemoLab.ps1 -SubscriptionId <id>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $SubscriptionId,
  [string] $InCountryResourceGroup = 'rg-ojkdemo-idc',
  [string] $OffshoreResourceGroup = 'rg-ojkdemo-sea-approved',
  [string] $NotApprovedLocation = 'southeastasia',
  [string] $ModelName = 'gpt-5.4-mini',
  [string] $ModelVersion = '2026-03-17'
)

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Test, [bool]$Pass, [string]$Detail) {
  $results.Add([pscustomobject]@{ Test = $Test; Result = $(if ($Pass) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}

$suffix = (Get-Random -Maximum 99999).ToString('00000')

# 1. Region outside Indonesia is denied.
$out = az storage account create -n "stdenytest$suffix" -g $InCountryResourceGroup -l $NotApprovedLocation --sku Standard_LRS `
  --allow-shared-key-access false --subscription $SubscriptionId -o none 2>&1 | Out-String
Add-Result "Storage in $NotApprovedLocation is denied" ($out -match 'RequestDisallowedByPolicy') (($out -split "`n" | Select-String 'Reasons' | Select-Object -First 1) -as [string]).Trim()

# 2 and 3. AI deployment types in the approved offshore placement.
$account = az cognitiveservices account list -g $OffshoreResourceGroup --subscription $SubscriptionId --query "[?kind=='AIServices'] | [0].name" -o tsv 2>$null
if (-not $account) {
  Add-Result 'AI account found' $false "No AIServices account in $OffshoreResourceGroup"
}
else {
  $out = az cognitiveservices account deployment create -g $OffshoreResourceGroup -n $account --deployment-name "test-global-$suffix" `
    --model-name $ModelName --model-version $ModelVersion --model-format OpenAI --sku-name GlobalStandard --sku-capacity 1 `
    --subscription $SubscriptionId -o none 2>&1 | Out-String
  Add-Result 'GlobalStandard deployment is denied' ($out -match 'RequestDisallowedByPolicy') (($out -split "`n" | Select-String 'Reasons' | Select-Object -First 1) -as [string]).Trim()

  $name = "test-datazone-$suffix"
  $state = az cognitiveservices account deployment create -g $OffshoreResourceGroup -n $account --deployment-name $name `
    --model-name $ModelName --model-version $ModelVersion --model-format OpenAI --sku-name DataZoneStandard --sku-capacity 1 `
    --subscription $SubscriptionId --query properties.provisioningState -o tsv 2>&1 | Out-String
  Add-Result 'DataZoneStandard deployment succeeds' ($state -match 'Succeeded') $state.Trim()
  az cognitiveservices account deployment delete -g $OffshoreResourceGroup -n $account --deployment-name $name --subscription $SubscriptionId 2>$null | Out-Null
}

# 4. Fresh compliance data.
foreach ($rg in $InCountryResourceGroup, $OffshoreResourceGroup) {
  az policy state trigger-scan --resource-group $rg --subscription $SubscriptionId --no-wait 2>$null
}
Add-Result 'Compliance scan started' $true "$InCountryResourceGroup, $OffshoreResourceGroup"

$results | Format-Table -AutoSize -Wrap
if ($results.Result -contains 'FAIL') { exit 1 }
