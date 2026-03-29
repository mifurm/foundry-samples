variable "vm_name" {
  description = "Name of the Windows 11 VM"
  type        = string
  default     = "vmfoundrymf"
}

variable "vm_size" {
  description = "Azure VM size for the Windows 11 VM"
  type        = string
  default     = "Standard_D4s_v5"
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
  vm_subnet_address_prefix = cidrsubnet(var.virtual_network_address_space, 8, 2)
}

resource "azurerm_subnet" "subnet_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.vm_subnet_address_prefix]
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-vm-${random_string.unique.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-vm-${random_string.unique.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  network_interface_id      = azurerm_network_interface.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_network_interface" "vm" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  depends_on = [
    azurerm_network_interface.vm,
    azurerm_network_interface_security_group_association.vm
  ]

  name                = var.vm_name
  computer_name       = var.vm_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size

  admin_username = "michalfu"
  admin_password = random_password.vm_admin_password.result

  network_interface_ids = [
    azurerm_network_interface.vm.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "microsoftwindowsdesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-pro"
    version   = "latest"
  }

  provision_vm_agent       = true
  enable_automatic_updates = true
  patch_mode               = "AutomaticByPlatform"
  patch_assessment_mode    = "AutomaticByPlatform"
  secure_boot_enabled      = true
  vtpm_enabled             = true
}

output "windows_vm_name" {
  description = "Name of the Windows 11 VM"
  value       = azurerm_windows_virtual_machine.vm.name
}

output "windows_vm_private_ip" {
  description = "Private IP address of the Windows 11 VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "windows_vm_public_ip" {
  description = "Public IP address of the Windows 11 VM"
  value       = azurerm_public_ip.vm.ip_address
}

output "vm_admin_username" {
  description = "Local administrator username for the Windows 11 VM"
  value       = "michalfu"
  sensitive   = true
}

output "vm_admin_password" {
  description = "Local administrator password for the Windows 11 VM"
  value       = random_password.vm_admin_password.result
  sensitive   = true
}