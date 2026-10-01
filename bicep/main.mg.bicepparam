using 'main.mg.bicep'

// Phase 1 (report only): every effect stays at Audit / AuditIfNotExists.
// Phase 2: switch effectDataLocation and selected preventive controls to Deny per management group.
param location = 'indonesiacentral'
param listOfAllowedLocations = [
  'indonesiacentral'
]
param allowedAiDeploymentTypes = [
  'Standard'
  'ProvisionedManaged'
]
param effectDataLocation = 'Audit'
param effectPreventive = 'Audit'
param effectDetective = 'AuditIfNotExists'
param effectKubernetes = 'Audit'
param effectCustomerManagedKey = 'Audit'
param effectResilience = 'Audit'
param includeArcMachines = 'true'
param enforcementMode = 'Default'
param assignmentName = 'ojk-checklist-202603'
