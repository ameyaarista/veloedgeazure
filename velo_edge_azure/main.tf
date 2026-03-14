terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.58.0"
    }
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  subscription_id                 = "xxx-yyyy-cccc-zzzz-aaaa-bbbb"  #azure-subsciption-id
  features {}
}
############################
# Variables
############################

variable "location" {
  default = "AustraliaEast"
}

variable "resource_group_name" {
  default = "velocloud-rg"
}

variable "virtual_machine_size" {
  default = "Standard_DS3_v2"
}

variable "edge_version" {
  default = "Virtual Edge 6.1.0"
}

variable "vco" {
  default = "vco301.velocloud.net"
}

variable "ignore_cert_errors" {
  default = "false"
}

variable "activation_key" {
  default = "XXXX-XXXX-XXXX-XXXX"
}

variable "edge_name" {
  default = "veloedgeazure"
}

variable "public_key" {}

variable "vnet_name" {
  default = "AzureVNET"
}

variable "vnet_prefix" {
  default = "10.6.0.0/16"
}

variable "public_subnet_name" {
  default = "default"
}

variable "public_subnet_prefix" {
  default = "10.6.0.0/24"
}

variable "private_subnet1_name" {
  default = "Private_SN11"
}

variable "private_subnet1_prefix" {
  default = "10.6.1.0/24"
}

variable "private_subnet2_name" {
  default = "Private_SN2"
}

variable "private_subnet2_prefix" {
  default = "10.6.2.0/24"
}

variable "edge_ge2_ip" {
  default = "10.6.1.4"
}

variable "edge_ge3_ip" {
  default = "10.6.2.4"
}

############################
# Resource Group
############################

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

############################
# Virtual Network
############################

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_prefix]
}

resource "azurerm_subnet" "public" {
  name                 = var.public_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.public_subnet_prefix]
}

resource "azurerm_subnet" "private1" {
  name                 = var.private_subnet1_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.private_subnet1_prefix]
}

resource "azurerm_subnet" "private2" {
  name                 = var.private_subnet2_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.private_subnet2_prefix]
}

############################
# Public IP
############################

resource "azurerm_public_ip" "edge_pip" {
  name                = "${var.edge_name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

############################
# NSG
############################

resource "azurerm_network_security_group" "edge_nsg" {
  name                = "VELO_vVCE_SG1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "VCMP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "2426"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

############################
# Network Interfaces
############################

resource "azurerm_network_interface" "nic1" {
  name                = "${var.edge_name}-nic-ge1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ip-ge1"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.edge_pip.id
  }
}

resource "azurerm_network_interface" "nic2" {
  name                = "${var.edge_name}-nic-ge2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ip-ge2"
    subnet_id                     = azurerm_subnet.private1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.edge_ge2_ip
  }
}

resource "azurerm_network_interface" "nic3" {
  name                = "${var.edge_name}-nic-ge3"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_forwarding_enabled = true

  ip_configuration {
    name                          = "ip-ge3"
    subnet_id                     = azurerm_subnet.private2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.edge_ge3_ip
  }
}

############################
# Cloud Init
############################

locals {
  cloud_init = <<EOF
#cloud-config
velocloud:
 vce:
  management_interface: false
  vco: ${var.vco}
  activation_code: ${var.activation_key}
  vco_ignore_cert_errors: ${var.ignore_cert_errors}
EOF
}

############################
# Virtual Machine
############################

resource "azurerm_linux_virtual_machine" "edge_vm" {
  name                = var.edge_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.virtual_machine_size
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.nic1.id,
    azurerm_network_interface.nic2.id,
    azurerm_network_interface.nic3.id
  ]

  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.public_key
  }

  custom_data = base64encode(local.cloud_init)

  plan {
    publisher = "arista-networks"
    product   = "velocloud-virtual-edge"
    name      = "velocloud_edge_6101"
  }

  source_image_reference {
    publisher = "arista-networks"
    offer     = "velocloud-virtual-edge"
    sku       = "velocloud_edge_6101"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}