using 'main.sub.bicep'

// Pilot in one subscription, report only.
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
