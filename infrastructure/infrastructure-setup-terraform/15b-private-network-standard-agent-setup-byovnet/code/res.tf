variable "agent_virtual_network_address_space" {
  description = "Address space for the VNet containing the delegated agent subnet"
  type        = string
  default     = "192.168.0.0/16"
}

variable "private_endpoint_virtual_network_address_space" {
  description = "Address space for the VNet containing the private endpoint subnet (used only if different from agent VNet)"
  type        = string
  default     = "192.168.0.0/16"
}

variable "agent_subnet_address_prefix" {
  description = "Address prefix for the delegated agent subnet"
  type        = string
  default     = "192.168.0.0/24"
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = string
  default     = "192.168.1.0/24"
}

locals {
  agent_subnet_parts = split("/", var.subnet_id_agent)
  pe_subnet_parts    = split("/", var.subnet_id_private_endpoint)

  agent_vnet_rg_name = local.agent_subnet_parts[4]
  agent_vnet_name    = local.agent_subnet_parts[8]
  agent_subnet_name  = local.agent_subnet_parts[10]

  pe_vnet_rg_name = local.pe_subnet_parts[4]
  pe_vnet_name    = local.pe_subnet_parts[8]
  pe_subnet_name  = local.pe_subnet_parts[10]

  same_vnet = local.agent_vnet_rg_name == local.pe_vnet_rg_name && local.agent_vnet_name == local.pe_vnet_name
}

resource "azurerm_resource_group" "resources" {
  provider = azurerm.workload_subscription

  name     = var.resource_group_name_resources
  location = var.location
}

resource "azurerm_resource_group" "dns" {
  provider = azurerm.infra_subscription

  name     = var.resource_group_name_dns
  location = var.location
}

resource "azurerm_virtual_network" "agent" {
  provider = azurerm.workload_subscription

  name                = local.agent_vnet_name
  location            = var.location
  resource_group_name = local.agent_vnet_rg_name == var.resource_group_name_resources ? azurerm_resource_group.resources.name : local.agent_vnet_rg_name
  address_space       = [var.agent_virtual_network_address_space]
}

resource "azurerm_virtual_network" "pe" {
  provider = azurerm.workload_subscription
  count    = local.same_vnet ? 0 : 1

  name                = local.pe_vnet_name
  location            = var.location
  resource_group_name = local.pe_vnet_rg_name == var.resource_group_name_resources ? azurerm_resource_group.resources.name : local.pe_vnet_rg_name
  address_space       = [var.private_endpoint_virtual_network_address_space]
}

resource "azurerm_subnet" "agent" {
  provider = azurerm.workload_subscription

  name                 = local.agent_subnet_name
  resource_group_name  = local.agent_vnet_rg_name
  virtual_network_name = azurerm_virtual_network.agent.name
  address_prefixes     = [var.agent_subnet_address_prefix]

  delegation {
    name = "Microsoft.App/environments"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoint" {
  provider = azurerm.workload_subscription

  name                = local.pe_subnet_name
  resource_group_name = local.pe_vnet_rg_name
  virtual_network_name = local.same_vnet ? azurerm_virtual_network.agent.name : azurerm_virtual_network.pe[0].name
  address_prefixes    = [var.private_endpoint_subnet_address_prefix]
}

resource "azurerm_private_dns_zone" "plz_cosmos_db" {
  provider = azurerm.infra_subscription

  name                = "privatelink.documents.azure.com"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone" "plz_ai_search" {
  provider = azurerm.infra_subscription

  name                = "privatelink.search.windows.net"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone" "plz_storage_blob" {
  provider = azurerm.infra_subscription

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone" "plz_cognitive_services" {
  provider = azurerm.infra_subscription

  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone" "plz_ai_services" {
  provider = azurerm.infra_subscription

  name                = "privatelink.services.ai.azure.com"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone" "plz_openai" {
  provider = azurerm.infra_subscription

  name                = "privatelink.openai.azure.com"
  resource_group_name = var.resource_group_name_dns

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_cosmos_db_link" {
  provider = azurerm.infra_subscription

  name                  = "cosmosdb-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_cosmos_db.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_ai_search_link" {
  provider = azurerm.infra_subscription

  name                  = "aisearch-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_ai_search.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_storage_blob_link" {
  provider = azurerm.infra_subscription

  name                  = "storage-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_storage_blob.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_cognitive_services_link" {
  provider = azurerm.infra_subscription

  name                  = "cogsvc-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_cognitive_services.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_ai_services_link" {
  provider = azurerm.infra_subscription

  name                  = "aiservices-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_ai_services.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_openai_link" {
  provider = azurerm.infra_subscription

  name                  = "openai-${replace(local.agent_vnet_name, "_", "-")}-link"
  resource_group_name   = var.resource_group_name_dns
  private_dns_zone_name = azurerm_private_dns_zone.plz_openai.name
  virtual_network_id    = azurerm_virtual_network.agent.id
  registration_enabled  = false
}
