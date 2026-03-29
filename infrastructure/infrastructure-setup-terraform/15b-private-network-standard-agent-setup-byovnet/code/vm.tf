variable "vm_name" {
  description = "Name of the Windows VM"
  type        = string
  default     = "vmfoundry"
}

variable "vm_size" {
  description = "Azure VM size for the Windows VM (minimum 4 vCPU / 16 GiB)"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "vm_admin_username" {
  description = "Local administrator username for the Windows VM"
  type        = string
  default     = "azureuser"
}

resource "random_password" "vm_admin_password" {
  length           = 24
  special          = true
  override_special = "!@#$%^&*()-_=+[]{}:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

locals {
  # Place the VM in a dedicated subnet inside the same VNet used by agents.
  vm_subnet_address_prefix = cidrsubnet(var.agent_virtual_network_address_space, 8, 2)
}

resource "azurerm_subnet" "vm" {
  provider = azurerm.workload_subscription

  depends_on = [
    azurerm_virtual_network.agent
  ]

  name                 = "snet-vm"
  resource_group_name  = local.agent_vnet_rg_name
  virtual_network_name = azurerm_virtual_network.agent.name
  address_prefixes     = [local.vm_subnet_address_prefix]
}

resource "azurerm_network_security_group" "vm" {
  provider = azurerm.workload_subscription

  name                = "nsg-vm-${random_string.unique.result}"
  location            = var.location
  resource_group_name = var.resource_group_name_resources

  security_rule {
    name                       = "Allow-RDP-From-VNet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  provider = azurerm.workload_subscription

  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_public_ip" "vm" {
  provider = azurerm.workload_subscription

  name                = "pip-vm-${random_string.unique.result}"
  location            = var.location
  resource_group_name = var.resource_group_name_resources
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  provider = azurerm.workload_subscription

  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name_resources

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  provider = azurerm.workload_subscription

  depends_on = [
    azurerm_network_interface.vm,
    azurerm_subnet_network_security_group_association.vm,
    azurerm_private_endpoint.pe_aifoundry,
    azapi_resource.ai_foundry_project_capability_host
  ]

  name                = var.vm_name
  computer_name       = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name_resources
  size                = var.vm_size

  admin_username = var.vm_admin_username
  admin_password = random_password.vm_admin_password.result

  network_interface_ids = [
    azurerm_network_interface.vm.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  provision_vm_agent         = true
  automatic_updates_enabled  = true
  patch_mode                 = "AutomaticByPlatform"
  patch_assessment_mode      = "AutomaticByPlatform"
  secure_boot_enabled        = true
  vtpm_enabled               = true
}

output "windows_vm_name" {
  description = "Name of the Windows VM"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "windows_vm_private_ip" {
  description = "Private IP address of the Windows VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "windows_vm_public_ip" {
  description = "Public IP address of the Windows VM"
  value       = azurerm_public_ip.vm.ip_address
}

output "vm_admin_username" {
  description = "Local administrator username for the Windows VM"
  value       = var.vm_admin_username
}

output "vm_admin_password" {
  description = "Local administrator password for the Windows VM"
  value       = random_password.vm_admin_password.result
  sensitive   = true
}
