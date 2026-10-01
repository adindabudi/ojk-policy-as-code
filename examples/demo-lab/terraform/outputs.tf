output "resource_group_names" {
  value = {
    in_country = azurerm_resource_group.idc.name
    offshore   = azurerm_resource_group.offshore.name
    simulator  = azurerm_resource_group.sim.name
  }
}

output "servers" {
  value = { for name, s in var.servers : name => s.scenario }
}

output "ai_account_name" {
  value = azurerm_cognitive_account.ai.name
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}

output "next_steps" {
  value = <<-EOT
    1. Connect the servers to Azure Arc (run from examples/demo-lab):
       ./scripts/Connect-ArcLab.ps1 -SimResourceGroup ${azurerm_resource_group.sim.name} -ArcResourceGroup ${azurerm_resource_group.idc.name} -Location ${var.location}
    2. Assign the OJK initiative to ${azurerm_resource_group.idc.name} and ${azurerm_resource_group.offshore.name} (run from terraform/):
       terraform apply -var-file=environments/demo-lab.tfvars
  EOT
}
