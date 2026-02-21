# ==========================================================
# OpenClaw GitHub Agent — Azure VM (Terraform)
# ==========================================================
# Provisions Azure infrastructure for the OpenClaw GitHub agent.
# VM configuration (Docker, Nginx, OpenClaw, firewall, etc.) is
# handled by Ansible after Terraform creates the VM.
#
# Architecture: Terraform (infra) → Cloud-Init (bootstrap) → Ansible (config)
#
# Resources created:
#   - Resource Group
#   - VNet / Subnet / NSG (SSH + HTTPS locked to deployer IP)
#   - Public IP with DNS label (<label>.<region>.cloudapp.azure.com)
#   - Key Vault (RBAC mode) with optional secrets
#   - Linux VM with minimal cloud-init bootstrap
#   - Auto-shutdown schedule
#
# Usage:
#   make deploy              # Terraform + cloud-init
#   make wait-for-cloud-init # Wait for bootstrap
#   make configure           # Ansible playbook
#   make openclaw-start      # Start services
# ==========================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      # Permanently delete Key Vault on destroy instead of soft-deleting
      purge_soft_delete_on_destroy = true
    }
  }
}

# ----------------------------------------------------------
# Variables
# ----------------------------------------------------------

variable "location" {
  default     = "westeurope"
  description = "Azure region for all resources"
  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region name (lowercase, no spaces)."
  }
}

variable "resource_group_name" {
  default     = "rg-openclaw"
  description = "Name of the Azure resource group"
}

variable "vm_name" {
  default     = "vm-openclaw"
  description = "Name of the virtual machine"
}

variable "vm_size" {
  default     = "Standard_B2s"
  description = "VM size (2 vCPU, 4 GB RAM)"
  validation {
    condition     = can(regex("^Standard_", var.vm_size))
    error_message = "VM size must start with 'Standard_'."
  }
}

variable "admin_username" {
  default     = "clawadmin"
  description = "Admin username for SSH and dashboard Basic Auth"
}

variable "admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Admin password for dashboard Basic Auth. Leave empty to auto-generate a 24-char random password."
}

variable "auto_shutdown_time" {
  default     = "2200"
  description = "Daily auto-shutdown time in UTC (e.g. 2200 = 22:00)"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto-shutdown time must be in HHMM format (0000-2359)."
  }
}

variable "github_pat" {
  type        = string
  default     = ""
  sensitive   = true
  description = "GitHub fine-grained personal access token (optional — skip to deploy without)"
}

variable "anthropic_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Anthropic API key for Claude models (optional — skip to deploy without)"
}

variable "allowed_ip" {
  type        = string
  default     = ""
  description = "Your public IP for SSH/HTTPS access. Leave empty to auto-detect via ipify.org."
}

variable "dns_label" {
  type        = string
  default     = ""
  description = "DNS label for the public IP (<label>.<region>.cloudapp.azure.com). Leave empty to auto-generate."
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Path to the SSH public key for VM authentication"
}

# ----------------------------------------------------------
# Data sources
# ----------------------------------------------------------

# Current deployer identity (used for Key Vault RBAC role assignments)
data "azurerm_client_config" "current" {}

# Auto-detect deployer's public IP for NSG rules (with fallback)
data "http" "my_ip" {
  url = "https://api.ipify.org"

  lifecycle {
    postcondition {
      condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", self.response_body))
      error_message = "Failed to detect public IP from ipify.org. Set var.allowed_ip manually."
    }
  }
}

# ----------------------------------------------------------
# Random resources (generated when defaults are empty)
# ----------------------------------------------------------

# Auto-generate a strong admin password if none was provided
resource "random_password" "admin" {
  count            = var.admin_password == "" ? 1 : 0
  length           = 24
  special          = true
  override_special = "!@#$%"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# Auto-generate a DNS label prefix if none was provided
resource "random_id" "dns" {
  count       = var.dns_label == "" ? 1 : 0
  byte_length = 4
  prefix      = "openclaw-"
}

# ----------------------------------------------------------
# Locals — resolved values used throughout the config
# ----------------------------------------------------------

locals {
  # Common tags for all Azure resources
  common_tags = {
    project     = "openclaw"
    environment = "dev"
    managed_by  = "terraform"
  }

  # Use provided IP or fall back to auto-detected IP
  allowed_ip = var.allowed_ip != "" ? var.allowed_ip : chomp(data.http.my_ip.response_body)

  # Use provided password or fall back to auto-generated one
  admin_password = var.admin_password != "" ? var.admin_password : random_password.admin[0].result

  # Use provided DNS label or fall back to auto-generated one
  dns_label = var.dns_label != "" ? var.dns_label : random_id.dns[0].hex

  # Fully qualified domain name for the VM's public IP
  fqdn = "${local.dns_label}.${var.location}.cloudapp.azure.com"
}

# ----------------------------------------------------------
# Resource Group
# ----------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ----------------------------------------------------------
# Networking — VNet, Subnet, NSG, Public IP, NIC
# ----------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = "vnet-openclaw"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "main" {
  name                 = "snet-openclaw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/26"]
}

# Network Security Group — only allows SSH, HTTPS and HTTP from the deployer's IP
resource "azurerm_network_security_group" "main" {
  name                = "nsg-openclaw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow SSH (port 22) from deployer IP only
  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${local.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Allow HTTPS (port 443) from deployer IP only
  security_rule {
    name                       = "Allow-HTTPS-MyIP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "${local.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Allow HTTP (port 80) from deployer IP — redirects to HTTPS via Nginx
  security_rule {
    name                       = "Allow-HTTP-MyIP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${local.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Explicit deny-all (defense in depth — makes intent clear)
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IP with a DNS label for a stable FQDN
resource "azurerm_public_ip" "main" {
  name                = "pip-openclaw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.dns_label
  tags                = local.common_tags
}

# Network interface — connects the VM to the subnet and public IP
resource "azurerm_network_interface" "main" {
  name                = "nic-openclaw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# ----------------------------------------------------------
# Key Vault (RBAC mode)
# ----------------------------------------------------------

resource "azurerm_key_vault" "main" {
  # Name must be globally unique — append hash of resource group ID
  name                       = "kv-openclaw-${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = local.common_tags

  # Firewall: deny by default, allow only deployer IP and VM public IP.
  # AzureServices bypass keeps platform integrations working without private endpoint.
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = compact([local.allowed_ip, azurerm_public_ip.main.ip_address])
  }
}

# Grant the deployer (current user/SP) "Key Vault Secrets Officer" role
# so Terraform can create/read/delete secrets
resource "azurerm_role_assignment" "deployer_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# -- Optional secrets (only created when values are provided) --

resource "azurerm_key_vault_secret" "github_pat" {
  count        = var.github_pat != "" ? 1 : 0
  name         = "github-pat"
  value        = var.github_pat
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.deployer_kv]
}

resource "azurerm_key_vault_secret" "anthropic_key" {
  count        = var.anthropic_key != "" ? 1 : 0
  name         = "anthropic-key"
  value        = var.anthropic_key
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.deployer_kv]
}

# -- Admin credentials (always created) --

resource "azurerm_key_vault_secret" "admin_username" {
  name         = "admin-username"
  value        = var.admin_username
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.deployer_kv]
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "admin-password"
  value        = local.admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.deployer_kv]
}

# ----------------------------------------------------------
# Linux VM
# ----------------------------------------------------------

resource "azurerm_linux_virtual_machine" "main" {
  name                            = var.vm_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = local.admin_password
  disable_password_authentication = true # SSH key-only; password used for dashboard Basic Auth

  tags                  = local.common_tags
  network_interface_ids = [azurerm_network_interface.main.id]

  # SSH public key for key-based authentication
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32
  }

  # Ubuntu 24.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # System-assigned managed identity for Key Vault access (no credentials needed)
  identity {
    type = "SystemAssigned"
  }

  # Cloud-init — minimal bootstrap only (installs Python3, pip, ACL).
  # All real configuration (Docker, Node.js, Nginx, OpenClaw, firewall,
  # security hardening) is handled by Ansible via 'make configure'.
  # No templatefile() needed — cloud-init.yml is a plain static file.
  custom_data = base64encode(file("${path.module}/cloud-init.yml"))
}

# Grant the VM's managed identity "Key Vault Secrets User" role
# so start.sh can read secrets at runtime without any stored credentials
resource "azurerm_role_assignment" "vm_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
}

# ----------------------------------------------------------
# Auto-Shutdown (cost protection)
# ----------------------------------------------------------

resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  virtual_machine_id    = azurerm_linux_virtual_machine.main.id
  location              = azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }
}

# ----------------------------------------------------------
# Outputs
# ----------------------------------------------------------

output "vm_public_ip" {
  value       = azurerm_public_ip.main.ip_address
  description = "Public IP address of the VM"
}

output "fqdn" {
  value       = local.fqdn
  description = "Fully qualified domain name of the VM"
}

output "dashboard_url" {
  value       = "https://${local.fqdn}"
  description = "URL for the OpenClaw dashboard (Basic Auth protected)"
}

output "ssh_command" {
  value       = "ssh ${var.admin_username}@${local.fqdn}"
  description = "SSH command to connect to the VM"
}

output "admin_username" {
  value       = var.admin_username
  description = "Admin username for SSH and dashboard"
}

output "admin_password" {
  value       = local.admin_password
  sensitive   = true
  description = "Admin password (sensitive — use 'terraform output -raw admin_password' to reveal)"
}

output "keyvault_name" {
  value       = azurerm_key_vault.main.name
  description = "Name of the Azure Key Vault storing secrets"
}

output "start_openclaw" {
  value       = "ssh ${var.admin_username}@${local.fqdn} 'cd ~/openclaw && ./start.sh'"
  description = "Command to start OpenClaw on the VM"
}

output "stop_vm" {
  value       = "az vm deallocate -g ${var.resource_group_name} -n ${var.vm_name}"
  description = "Command to stop (deallocate) the VM"
}

output "start_vm" {
  value       = "az vm start -g ${var.resource_group_name} -n ${var.vm_name}"
  description = "Command to start the VM"
}

output "get_password" {
  value       = "az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name admin-password --query value -o tsv"
  description = "Command to retrieve admin password from Key Vault"
}
