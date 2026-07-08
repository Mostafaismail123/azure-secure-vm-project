# main.tf
# ==============================================================================
# Terraform configuration — Resource Group + VNet + Subnet + NSG + VM
# Rebuilds the same secure Azure infrastructure as the Portal and CLI versions
# in this repository, this time fully declared as code.
# ==============================================================================

# -----------------------------------------------------------------------------
# 1. Provider
#    Tells Terraform which cloud this configuration targets (Azure).
# -----------------------------------------------------------------------------
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# 2. Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "rg-portfolio-tf"
  location = "westeurope"
}

# -----------------------------------------------------------------------------
# 3. Virtual Network + Subnet
#    References azurerm_resource_group.main instead of hardcoding the name
#    again, so every resource stays in sync if the resource group is ever
#    renamed. This also tells Terraform the dependency order automatically.
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-portfolio-tf"
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.2.1.0/24"]
}

# -----------------------------------------------------------------------------
# 4. Network Security Group + rule
#    Default-deny inbound, with a single allow rule scoped to one trusted IP.
# -----------------------------------------------------------------------------
resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-tf"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "YOUR.IP.ADDRESS.HERE/32" # replace with your own public IP
    destination_address_prefix = "*"
  }
}

# -----------------------------------------------------------------------------
# 5. Associate the NSG with the subnet
# -----------------------------------------------------------------------------
resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# -----------------------------------------------------------------------------
# 6. Public IP
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "vm" {
  name                = "vm-app-tf-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -----------------------------------------------------------------------------
# 7. Network Interface — connects the VM to the subnet and the public IP
# -----------------------------------------------------------------------------
resource "azurerm_network_interface" "vm" {
  name                = "vm-app-tf-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# -----------------------------------------------------------------------------
# 8. Virtual Machine
# -----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "app" {
  name                = "vm-app-tf"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2ts_v2"
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.vm.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub") # path to your own public key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# -----------------------------------------------------------------------------
# 9. Output — prints the VM's public IP after apply, for easy SSH access
# -----------------------------------------------------------------------------
output "vm_public_ip" {
  value = azurerm_public_ip.vm.ip_address
}
