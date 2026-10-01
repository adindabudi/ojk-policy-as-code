data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
}

# rg-<prefix>-idc           : in-country estate (Arc-enabled servers and Azure resources), gets the OJK assignment
# rg-<prefix>-sea-approved  : simulated OJK-approved offshore placement (AI), gets the assignment plus an exemption
# rg-<prefix>-onprem-sim    : Azure VMs that play the on-premises servers, not assigned
resource "azurerm_resource_group" "idc" {
  name     = "rg-${var.prefix}-idc"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "offshore" {
  name     = "rg-${var.prefix}-sea-approved"
  location = var.offshore_location
  tags     = var.tags
}

resource "azurerm_resource_group" "sim" {
  name     = "rg-${var.prefix}-onprem-sim"
  location = var.location
  tags     = merge(var.tags, { simulates = "on-premises datacenter" })
}

# ---------------------------------------------------------------------------
# Simulated on-premises network: private subnet, outbound through NAT only.
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "sim" {
  name                = "vnet-${var.prefix}-onprem"
  location            = azurerm_resource_group.sim.location
  resource_group_name = azurerm_resource_group.sim.name
  address_space       = ["10.50.0.0/24"]
  tags                = var.tags
}

resource "azurerm_network_security_group" "servers" {
  name                = "nsg-${var.prefix}-servers"
  location            = azurerm_resource_group.sim.location
  resource_group_name = azurerm_resource_group.sim.name
  tags                = var.tags
}

resource "azurerm_subnet" "servers" {
  name                            = "snet-servers"
  resource_group_name             = azurerm_resource_group.sim.name
  virtual_network_name            = azurerm_virtual_network.sim.name
  address_prefixes                = ["10.50.0.0/26"]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "servers" {
  subnet_id                 = azurerm_subnet.servers.id
  network_security_group_id = azurerm_network_security_group.servers.id
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.prefix}-nat"
  location            = azurerm_resource_group.sim.location
  resource_group_name = azurerm_resource_group.sim.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    # Some tenants append IP tags by policy.
    ignore_changes = [ip_tags]
  }
}

resource "azurerm_nat_gateway" "sim" {
  name                = "nat-${var.prefix}-onprem"
  location            = azurerm_resource_group.sim.location
  resource_group_name = azurerm_resource_group.sim.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "sim" {
  nat_gateway_id       = azurerm_nat_gateway.sim.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "servers" {
  subnet_id      = azurerm_subnet.servers.id
  nat_gateway_id = azurerm_nat_gateway.sim.id
}

# ---------------------------------------------------------------------------
# Windows Server VMs that play on-premises servers (connected to Arc later).
# ---------------------------------------------------------------------------
resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_network_interface" "server" {
  for_each = var.servers

  name                = "nic-${each.key}"
  location            = azurerm_resource_group.sim.location
  resource_group_name = azurerm_resource_group.sim.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.servers.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "server" {
  for_each = var.servers

  name                  = each.key
  computer_name         = each.key
  location              = azurerm_resource_group.sim.location
  resource_group_name   = azurerm_resource_group.sim.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.server[each.key].id]

  # Keep the image as it is: no automatic patching, so the missing updates stay visible.
  patch_mode                = "Manual"
  automatic_updates_enabled = false
  patch_assessment_mode     = "ImageDefault"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = each.value.image_sku
    version   = each.value.image_version
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, { scenario = each.value.scenario })

  lifecycle {
    ignore_changes = [identity, tags]
  }
}

# ---------------------------------------------------------------------------
# Azure resources in the approved in-country region.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "sample" {
  name                              = "st${var.prefix}${local.suffix}"
  location                          = azurerm_resource_group.idc.location
  resource_group_name               = azurerm_resource_group.idc.name
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  public_network_access             = "Disabled"
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags
}

resource "azurerm_key_vault" "sample" {
  name                          = "kv-${var.prefix}-${local.suffix}"
  location                      = azurerm_resource_group.idc.location
  resource_group_name           = azurerm_resource_group.idc.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# ---------------------------------------------------------------------------
# Simulated OJK-approved offshore placement: AI in the Asia Pacific data zone.
# ---------------------------------------------------------------------------
resource "azurerm_cognitive_account" "ai" {
  name                          = "ai-${var.prefix}-${local.suffix}"
  location                      = azurerm_resource_group.offshore.location
  resource_group_name           = azurerm_resource_group.offshore.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = "ai-${var.prefix}-${local.suffix}"
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cognitive_deployment" "approved" {
  name                 = var.ai_model.deployment_name
  cognitive_account_id = azurerm_cognitive_account.ai.id

  model {
    format  = "OpenAI"
    name    = var.ai_model.name
    version = var.ai_model.version
  }

  sku {
    name     = var.ai_model.sku
    capacity = var.ai_model.capacity
  }
}
