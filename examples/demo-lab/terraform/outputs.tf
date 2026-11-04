output "resource_group_names" {
  description = "Lab resource groups: in-country estate, approved offshore placement and the on-premises simulator."
  value = {
    in_country = azurerm_resource_group.idc.name
    offshore   = azurerm_resource_group.offshore.name
    simulator  = azurerm_resource_group.sim.name
  }
}

output "servers" {
  description = "Lab servers and the scenario each one plays."
  value       = { for name, s in var.servers : name => s.scenario }
}

output "ai_account_name" {
  description = "Foundry (AIServices) account in the approved offshore placement."
  value       = azurerm_cognitive_account.ai.name
}

output "admin_username" {
  description = "Local administrator name on the lab VMs."
  value       = var.admin_username
}

output "admin_password" {
  description = "Generated local administrator password. Read it with: terraform output -raw admin_password"
  value       = random_password.admin.result
  sensitive   = true
}

output "next_steps" {
  description = "What to run after the lab is created."
  value       = <<-EOT
    1. Connect the servers to Azure Arc (run from examples/demo-lab):
       ./scripts/Connect-ArcLab.ps1 -SimResourceGroup ${azurerm_resource_group.sim.name} -ArcResourceGroup ${azurerm_resource_group.idc.name} -Location ${var.location}
    2. Assign the OJK initiative to ${azurerm_resource_group.idc.name} and ${azurerm_resource_group.offshore.name} (run from terraform/):
       terraform apply -var-file=environments/demo-lab.tfvars
  EOT
}
