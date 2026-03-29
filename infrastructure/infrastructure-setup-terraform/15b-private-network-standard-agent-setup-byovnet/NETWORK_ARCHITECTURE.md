# Network Architecture - 15b Private Network Standard Agent Setup (BYOVNET)

## Overview
This Terraform configuration deploys Azure AI Foundry with agents in a private network using a bring-your-own VNet (BYOVNET) model. All subnets reside in a single virtual network with private DNS zone integration for secure service resolution.

## Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  WORKLOAD SUBSCRIPTION (resource_group_name_resources: "myfoundryrg")      │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  Virtual Network: agent_vnet (192.168.0.0/16)                      │   │
│  │                                                                     │   │
│  │  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────┐ │   │
│  │  │  Agent Subnet        │  │  PE Subnet           │  │ VM Subnet│ │   │
│  │  │  192.168.0.0/24      │  │  192.168.1.0/24      │  │192.168.2/24 │   │
│  │  │                      │  │                      │  │          │ │   │
│  │  │ + Delegated to       │  │ • Private Endpoints: │  │ • vmfoundry │   │
│  │  │   Microsoft.App/     │  │   - Storage (blob)   │  │   VM (4vCPU) │   │
│  │  │   environments       │  │   - CosmosDB         │  │   16GB RAM   │   │
│  │  │                      │  │   - AI Search        │  │   Windows    │   │
│  │  │ • Standard Agents    │  │   - AI Foundry       │  │   2022-g2    │   │
│  │  │ • NSG: Allow agent   │  │                      │  │             │   │
│  │  │   traffic            │  │ • NSG: Allow private │  │ • Public IP  │   │
│  │  │                      │  │   endpoint access    │  │   (Static)   │   │
│  │  │                      │  │                      │  │             │   │
│  │  │                      │  │                      │  │ • NSG: RDP   │   │
│  │  │                      │  │                      │  │   from VNet  │   │
│  │  └──────────────────────┘  └──────────────────────┘  └──────────┘ │   │
│  │                                                                     │   │
│  │  NSG Associations:                                                 │   │
│  │  • agent_subnet ← NSG (delegated)                                  │   │
│  │  • private_endpoint_subnet ← NSG (pe rules)                        │   │
│  │  • vm_subnet ← NSG (vm rules)                                      │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Private Endpoints (in PE Subnet 192.168.1.0/24):                          │
│  ├─ pe_storage → blob.core.windows.net                                    │
│  ├─ pe_cosmosdb → documents.azure.com                                     │
│  ├─ pe_aisearch → search.windows.net                                      │
│  └─ pe_aifoundry → cognitiveservices.azure.com                            │
│                                                                             │
│  Key Resources:                                                            │
│  • AI Foundry: "aifoundry<unique>" (injected into agent subnet)           │
│  • AI Project: "project<unique>"                                          │
│  • Storage Account: "aifoundry<unique>storage"                            │
│  • CosmosDB: "aifoundry<unique>cosmosdb"                                  │
│  • AI Search: "aifoundry<unique>search"                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  INFRASTRUCTURE SUBSCRIPTION (resource_group_name_dns: "myinfrargrg")      │
│                                                                             │
│  Private DNS Zones (linked to agent VNet 192.168.0.0/16):                 │
│  ├─ privatelink.blob.core.windows.net                                     │
│  ├─ privatelink.documents.azure.com                                       │
│  ├─ privatelink.search.windows.net                                        │
│  ├─ privatelink.cognitiveservices.azure.com                               │
│  ├─ privatelink.services.ai.azure.com                                     │
│  └─ privatelink.openai.azure.com                                          │
│                                                                             │
│  Virtual Network Links:                                                   │
│  • All DNS zones linked to: agent_vnet (192.168.0.0/16)                   │
│  • Link naming pattern: <resource>-<vnet-name>-link                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Communication Flow

```
┌─────────────┐
│   vmfoundry │ (192.168.2.x, Public IP: <static>)
│   Windows   │
│   2022-g2   │
└──────┬──────┘
       │
       │ (VNet Internal)
       ▼
    agent_vnet (192.168.0.0/16)
       │
       ├─────────────────────────────┬────────────────┬───────────────┐
       │                             │                │               │
    ┌──▼─────┐                  ┌────▼────┐      ┌────▼────┐    ┌─────▼──┐
    │ Agent  │                  │ Private │      │ Storage │    │Foundry │
    │Subnet  │                  │Endpoint │      │Account  │    │ & AI   │
    │        │                  │Subnet   │      │(PE)     │    │Search  │
    └────────┘                  └────┬────┘      └─────────┘    │(PE)    │
                                     │                          └────────┘
                                     │
      ┌──────────────────────────────┼──────────────────────────────┐
      │                              │                              │
      ▼                              ▼                              ▼
Private DNS Resolution via Links:
• queries to *.blob.core.windows.net → resolved via PE NIC
• queries to *.documents.azure.com → resolved via PE NIC
• queries to *.cognitiveservices.azure.com → resolved via PE NIC
• queries to *.services.ai.azure.com → resolved via PE NIC
• queries to *.openai.azure.com → resolved via PE NIC
```

## Key Variables & Naming

| Component | Variable Name | Default/Format | Example |
|-----------|---------------|-----------------|---------|
| **VNets** | | | |
| Agent VNet Name | (derived from `subnet_id_agent`) | - | `agent_vnet` |
| Agent VNet CIDR | `agent_virtual_network_address_space` | `192.168.0.0/16` | |
| PE VNet | `same_vnet` logic | Used only if different | (same as agent VNet in 15b) |
| **Subnets** | | | |
| Agent Subnet Name | (derived from `subnet_id_agent`) | - | `agent_subnet` |
| Agent Subnet CIDR | `agent_subnet_address_prefix` | `192.168.0.0/24` | |
| PE Subnet Name | (derived from `subnet_id_private_endpoint`) | - | `pe_subnet` |
| PE Subnet CIDR | `private_endpoint_subnet_address_prefix` | `192.168.1.0/24` | |
| VM Subnet | Hardcoded in `vm.tf` | `192.168.2.0/24` | |
| **VM** | | | |
| VM Name | `vm_name` | `vmfoundry` | |
| VM Size | `vm_size` | `Standard_D4s_v5` (4vCPU, 16GB) | |
| VM Admin User | `vm_admin_username` | `azureuser` | |
| VM Public IP | Generated | `pip-vm-<unique>` | |
| **Resources** | | | |
| Unique Suffix | `random_string.unique` | 4-digit random | e.g., `a1b2` |
| Storage Account | Pattern | `aifoundry<unique>storage` | `aifoundrya1b2storage` |
| CosmosDB | Pattern | `aifoundry<unique>cosmosdb` | `aifoundrya1b2cosmosdb` |
| AI Search | Pattern | `aifoundry<unique>search` | `aifoundrya1b2search` |
| AI Foundry | Pattern | `aifoundry<unique>` | `aifoundrya1b2` |
| AI Project | Pattern | `project<unique>` | `projecta1b2` |

## Network Security Rules

### Agent Subnet NSG
- Delegated to `Microsoft.App/environments`

### Private Endpoint Subnet NSG
- Implicitly allows private endpoint traffic via subnet associations

### VM Subnet NSG
```
Inbound Rules:
├─ Allow RDP (3389/TCP) from VirtualNetwork
└─ Implicit deny all other external traffic

Outbound Rules:
└─ Allow all (default)
```

## DNS Resolution

All resources in the agent_vnet can resolve private endpoints via linked DNS zones:

- `*.blob.core.windows.net` → Private endpoint IP (storage account)
- `*.documents.azure.com` → Private endpoint IP (CosmosDB)
- `*.search.windows.net` → Private endpoint IP (AI Search)
- `*.cognitiveservices.azure.com` → Private endpoint IP (AI Foundry)
- `*.services.ai.azure.com` → Private endpoint IP (AI Services)
- `*.openai.azure.com` → Private endpoint IP (OpenAI)

## Peering & Transit

**In 15b (BYOVNET) scenario:**
- No VNet peering (single VNet used)
- All resources communicate within agent_vnet via RFC1918 addresses
- Private endpoints use PE subnet for secure service connectivity

**If transitioning to multi-VNet (future):**
- Would require VNet peering between agent_vnet and external networks
- DNS propagation across peered VNets via shared private DNS zones
