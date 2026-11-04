// Records an OJK-approved (or temporary) offshore placement as a policy exemption on one resource group.
// Checklist: Part 2 B-II #9 (POJK 11/2022 Art. 35(2) and 36(1)(j)) and Part 2 A-I #1.
// The exemption waives only the location controls. To allow AI deployment types that process data outside the
// resource's geography, list them in approvedAiDeploymentTypes: the resource group then gets its own assignment of
// the AI policy with only those types, and types outside the approval (for example Global*) stay blocked.
// Deploy with: az deployment group create -g <rg> -f exemption-ojk-offshore.bicep -p policyAssignmentId=... ojkApprovalReference=...
targetScope = 'resourceGroup'

@description('Resource ID of the OJK checklist initiative assignment that covers this resource group.')
param policyAssignmentId string

@description('OJK approval letter number or internal approval ID.')
param ojkApprovalReference string

@description('Why the system is placed outside Indonesia and where the re-placement plan is documented.')
param justification string

@description('UTC expiry, for example 2027-03-31T00:00:00Z. Leave empty only for a permanent OJK approval.')
param expiresOn string = ''

@description('AI deployment types (sku.name) covered by the approval, for example [\'DataZoneStandard\']. Empty keeps the initiative default.')
param approvedAiDeploymentTypes array = []

@description('Resource ID of the custom policy definition ojk-ai-approved-deployment-types. Required when approvedAiDeploymentTypes is not empty.')
param aiPolicyDefinitionId string = ''

@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
@description('Effect of the narrower AI assignment. Use the same value as effectDataLocation on the initiative.')
param aiEffect string = 'Deny'

@description('Enforcement mode of the narrower AI assignment. Use the same value as enforcementMode on the initiative.')
@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string = 'Default'

@description('Exemption name, 64 characters at most.')
@maxLength(64)
param exemptionName string = 'ojk-offshore-${uniqueString(resourceGroup().id)}'

var narrowAi = !empty(approvedAiDeploymentTypes)

resource aiAssignment 'Microsoft.Authorization/policyAssignments@2025-11-01' = if (narrowAi) {
  name: take('ojk-ai-${exemptionName}', 64)
  properties: {
    displayName: 'OJK approved AI deployment types - ${ojkApprovalReference}'
    description: 'AI deployment types approved for this offshore placement: ${join(approvedAiDeploymentTypes, ', ')}.'
    policyDefinitionId: aiPolicyDefinitionId
    enforcementMode: enforcementMode
    parameters: {
      effect: { value: aiEffect }
      allowedDeploymentTypes: { value: approvedAiDeploymentTypes }
    }
    nonComplianceMessages: [
      {
        message: 'AI deployment type is outside the OJK approval for this placement (${ojkApprovalReference}). Approved types: ${join(approvedAiDeploymentTypes, ', ')}.'
      }
    ]
  }
}

// Policy exemptions don't have a GA API version yet, so this resource uses a preview version.
resource exemption 'Microsoft.Authorization/policyExemptions@2024-12-01-preview' = {
  name: exemptionName
  properties: {
    policyAssignmentId: policyAssignmentId
    policyDefinitionReferenceIds: concat([
      'dl-allowed-locations'
      'dl-allowed-rg-locations'
    ], narrowAi ? [ 'dl-ai-deployment-types' ] : [])
    exemptionCategory: 'Waiver'
    displayName: 'OJK offshore placement - ${ojkApprovalReference}'
    description: justification
    expiresOn: empty(expiresOn) ? null : expiresOn
    metadata: {
      ojkApprovalReference: ojkApprovalReference
      checklistReference: 'Part 2 B-II #9 / A-I #1'
      approvedAiDeploymentTypes: approvedAiDeploymentTypes
    }
  }
  dependsOn: [
    aiAssignment
  ]
}

output exemptionId string = exemption.id
output aiAssignmentId string = narrowAi ? aiAssignment.id : ''
