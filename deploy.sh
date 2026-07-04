#!/bin/bash
# ==============================================================================
# Azure Secure Linux VM — CLI Deployment Script
# ==============================================================================
# Rebuilds the same infrastructure as the Portal-based project (see README.md),
# but entirely through the Azure CLI. Same architecture, same security model,
# fully scripted and repeatable.
#
# Prerequisites:
#   - Azure CLI installed (az --version)
#   - Logged in: az login
#   - An active Azure subscription selected
#
# Usage:
#   1. Edit the variables below (especially MY_IP)
#   2. chmod +x deploy.sh
#   3. ./deploy.sh
# ==============================================================================

set -e  # stop immediately if any command fails

# ------------------------------------------------------------------------------
# Variables — edit these before running
# ------------------------------------------------------------------------------
RESOURCE_GROUP="rg-portfolio-cli"
LOCATION="westeurope"
VNET_NAME="vnet-portfolio-cli"
VNET_PREFIX="10.1.0.0/16"
SUBNET_NAME="snet-app"
SUBNET_PREFIX="10.1.1.0/24"
NSG_NAME="nsg-app-cli"
VM_NAME="vm-app-cli"
VM_SIZE="Standard_B2ts_v2"
ADMIN_USERNAME="azureuser"

# IMPORTANT: replace with your own public IP (find it at whatismyipaddress.com).
# Home/mobile ISPs often rotate this — if SSH times out later, this is the
# first thing to check and update via `az network nsg rule update`.
MY_IP="203.0.113.10/32"

# ------------------------------------------------------------------------------
# 1. Resource Group — logical container for everything below
# ------------------------------------------------------------------------------
echo "Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

# ------------------------------------------------------------------------------
# 2. Virtual Network + Subnet
#    A dedicated address space, separate from any other project's network,
#    to avoid conflicts if these networks are ever peered together later.
# ------------------------------------------------------------------------------
echo "Creating virtual network and subnet..."
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefix "$VNET_PREFIX" \
  --subnet-name "$SUBNET_NAME" \
  --subnet-prefix "$SUBNET_PREFIX"

# ------------------------------------------------------------------------------
# 3. Network Security Group — the firewall
#    Default behavior is deny-all inbound. We add exactly one allow rule:
#    SSH, from a single trusted IP only. Attached at the SUBNET level (not
#    the NIC) so any future VM placed in this subnet inherits the same rule.
# ------------------------------------------------------------------------------
echo "Creating network security group..."
az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NSG_NAME"

echo "Adding SSH allow rule for trusted IP..."
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name Allow-SSH-MyIP \
  --priority 1000 \
  --source-address-prefixes "$MY_IP" \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp

echo "Associating NSG with the subnet..."
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME"

# ------------------------------------------------------------------------------
# 4. Virtual Machine
#    --nsg "" tells Azure not to create a second NSG on the NIC — the subnet
#    is already protected, so a NIC-level NSG would just be redundant.
# ------------------------------------------------------------------------------
echo "Creating virtual machine (this takes a minute or two)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --image Ubuntu2404 \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --nsg "" \
  --public-ip-sku Standard \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --generate-ssh-keys

# ------------------------------------------------------------------------------
# Done — print connection info
# ------------------------------------------------------------------------------
PUBLIC_IP=$(az vm show -d --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query publicIps -o tsv)
echo ""
echo "Deployment complete."
echo "Connect with: ssh $ADMIN_USERNAME@$PUBLIC_IP"
echo ""
echo "To tear everything down and stop all charges:"
echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
