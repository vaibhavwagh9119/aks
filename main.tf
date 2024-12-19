provider "azurerm" {
  features {}
  subscription_id = "aa3acf2e-7f3b-4bda-b27d-50dcf015a63a"
}

# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "myResourceGroup"
  location = "East US"
}

# Create Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "myVNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create Subnet for AKS Nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aksSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Create Subnet for Private Endpoints
resource "azurerm_subnet" "private_endpoint_subnet" {
  name                 = "privateEndpointSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Private DNS Zone
resource "azurerm_private_dns_zone" "aks_private_dns" {
  name                = "privatelink.azmk8s.io"
  resource_group_name = azurerm_resource_group.rg.name
}

# Create AKS Cluster (Private)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "myAKSCluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "myaksdns"
  private_cluster_enabled = true

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }


}

# Create Private Endpoint for AKS Control Plane (API Server)
resource "azurerm_private_endpoint" "aks_private_endpoint" {
  name                = "aksPrivateEndpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "aksPrivateLinkServiceConnection"
    private_connection_resource_id = azurerm_kubernetes_cluster.aks.id  # Correctly reference the AKS cluster ID
    is_manual_connection           = false
  }
}

# Link the Private DNS Zone to the VNet
resource "azurerm_private_dns_zone_virtual_network_link" "aks_dns_link" {
  name                       = "aksPrivateDnsLink"
  resource_group_name        = azurerm_resource_group.rg.name
  private_dns_zone_name     = azurerm_private_dns_zone.aks_private_dns.name
  virtual_network_id        = azurerm_virtual_network.vnet.id
  registration_enabled      = true
}

# Create a Network Security Group (NSG)
resource "azurerm_network_security_group" "nsg" {
  name                = "myNSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
resource "azurerm_network_interface" "private_endpoint_nic" {
  name                = "private_endpoint_nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private_endpoint_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}
# Associate NSG with Private Endpoint Network Interface
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.private_endpoint_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
