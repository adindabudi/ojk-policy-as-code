// Deploys the OJK checklist initiative at subscription scope (pilot or lab).
// For production, prefer main.mg.bicep so every subscription inherits the same assignment.
targetScope = 'subscription'

@description('Region of the policy assignment\'s managed identity. Keep it in an allowed region.')
param location string = 'indonesiacentral'

@description('Regions allowed for resources and resource groups. Azure Arc resources keep their metadata in this region.')
param listOfAllowedLocations array = [
  'indonesiacentral'
]

@description('Foundry / Azure OpenAI deployment types (sku.name) whose processing location is approved.')
param allowedAiDeploymentTypes array = [
  'Standard'
  'ProvisionedManaged'
]

@description('Effect of the location and AI deployment type controls (OJK-01). Switch to Deny after every approved offshore placement has an exemption.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effectDataLocation string = 'Audit'

@description('Effect of the configuration controls that support Deny, such as public network access, TLS versions and local authentication.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effectPreventive string = 'Audit'

@description('Effect of the AuditIfNotExists controls, such as Defender plans, logs, machine configuration, update assessment and backup.')
@allowed([
  'AuditIfNotExists'
  'Disabled'
])
param effectDetective string = 'AuditIfNotExists'

@description('Effect of the Kubernetes controls for AKS and Azure Arc-enabled Kubernetes clusters.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effectKubernetes string = 'Audit'

@description('Effect of the customer-managed key controls (storage, SQL, Foundry). Audit or Disabled only, because the key choice depends on the data.')
@allowed([
  'Audit'
  'Disabled'
])
param effectCustomerManagedKey string = 'Audit'

@description('Effect of the zone redundancy controls. These built-ins are in preview: set Disabled if you don\'t use preview policies in production.')
@allowed([
  'Audit'
  'Deny'
  'Disabled'
])
param effectResilience string = 'Audit'

@description('\'true\' evaluates Azure Arc-enabled servers in the machine configuration controls (security baseline and secure protocols).')
@allowed([
  'true'
  'false'
])
param includeArcMachines string = 'true'

@description('Resource types that must have diagnostic settings (OJK-07).')
param diagnosticSettingsResourceTypes array = [
  'Microsoft.ApiManagement/service'
  'Microsoft.ContainerService/managedClusters'
  'Microsoft.Network/applicationGateways'
  'Microsoft.Network/azureFirewalls'
  'Microsoft.Web/sites'
]

@description('Resource group in each subscription where the Service Health alert rule is expected (OJK-08). rg-serviceHealthAlert matches the Azure landing zone default.')
param serviceHealthAlertResourceGroupName string = 'rg-serviceHealthAlert'

@description('DoNotEnforce evaluates compliance without applying Deny effects.')
@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string = 'Default'

@description('Policy assignment name.')
@maxLength(64)
param assignmentName string = 'ojk-checklist-202603'

@description('Scopes excluded from the assignment, for example a sandbox resource group.')
param notScopes array = []

// definitionVersion pins each built-in to a major version (for example 2.*.*), so a new major version of a
// built-in becomes a reviewed change in the mapping instead of arriving on the next deployment.
var mapping = loadJsonContent('../mapping/ojk-policy-mapping.json')
var aiDefinition = loadJsonContent('../policies/ai-approved-deployment-types.json')
var customReference = 'custom:${aiDefinition.name}'

resource aiDeploymentTypes 'Microsoft.Authorization/policyDefinitions@2025-11-01' = {
  name: aiDefinition.name
  properties: aiDefinition.properties
}

resource initiative 'Microsoft.Authorization/policySetDefinitions@2025-11-01' = {
  name: mapping.initiative.name
  properties: {
    policyType: 'Custom'
    displayName: mapping.initiative.displayName
    description: mapping.initiative.description
    metadata: mapping.initiative.metadata
    parameters: mapping.initiative.parameters
    policyDefinitionGroups: mapping.groups
    // map() keeps each member's [parameters('...')] values as text for Azure Policy. A for-loop compiles to an ARM
    // copy loop, which evaluates them again against this template's parameters, and the deployment then fails
    // with UnusedPolicyParameters.
    policyDefinitions: map(mapping.members, m => {
      policyDefinitionReferenceId: m.referenceId
      policyDefinitionId: m.definitionId == customReference
        ? aiDeploymentTypes.id
        : tenantResourceId('Microsoft.Authorization/policyDefinitions', m.definitionId)
      definitionVersion: m.?definitionVersion
      parameters: m.parameters
      groupNames: m.groups
    })
  }
}

resource assignment 'Microsoft.Authorization/policyAssignments@2025-11-01' = {
  name: assignmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: mapping.initiative.displayName
    description: 'Bank-side technical controls from the OJK FSI checklist (Mar 2026) for Azure and Azure Arc resources.'
    policyDefinitionId: initiative.id
    enforcementMode: enforcementMode
    notScopes: notScopes
    parameters: {
      listOfAllowedLocations: { value: listOfAllowedLocations }
      allowedAiDeploymentTypes: { value: allowedAiDeploymentTypes }
      effectDataLocation: { value: effectDataLocation }
      effectPreventive: { value: effectPreventive }
      effectDetective: { value: effectDetective }
      effectKubernetes: { value: effectKubernetes }
      effectCustomerManagedKey: { value: effectCustomerManagedKey }
      effectResilience: { value: effectResilience }
      includeArcMachines: { value: includeArcMachines }
      diagnosticSettingsResourceTypes: { value: diagnosticSettingsResourceTypes }
      serviceHealthAlertResourceGroupName: { value: serviceHealthAlertResourceGroupName }
    }
    nonComplianceMessages: [
      {
        message: 'Not compliant with the OJK checklist technical controls. Check the policy group (OJK-01 to OJK-09) for the checklist reference, or request an exemption with the OJK approval reference.'
      }
      {
        policyDefinitionReferenceId: 'dl-allowed-locations'
        message: 'Region is not approved. Placing electronic systems outside Indonesia needs OJK approval (POJK 11/2022). Record the approval as a policy exemption.'
      }
      {
        policyDefinitionReferenceId: 'dl-ai-deployment-types'
        message: 'AI deployment type is not approved. Global and DataZone types can process data outside Indonesia.'
      }
    ]
  }
}

output customDefinitionId string = aiDeploymentTypes.id
output initiativeId string = initiative.id
output assignmentId string = assignment.id
output assignmentPrincipalId string = assignment.identity.principalId
