A ramp-up project for Senior Software Engineers at Microsoft, architecturing a globally scalable low-latency API utilising:

- Orleans 10
- AKS (Kubernetes 1.33)
- CosmosDB (AAD auth via workload identity)
- Azure Container Registry
- Azure Key Vault
- Azure Front Door Premium
- ASP.NET Core 10 / .NET Aspire
- Bicep for IaC
- GitHub Actions CI/CD

---

### Application Layer

The scenario being scaled is a replica of Ticketmaster, the distribution of events with tickets purchasable globally. Atomic purchases of specific seats, allocation of categorised sales (pre-sale, early bird, general admission etc) and event history offers a breadth of functionality to demonstrate the utility of the tech stack.

The architecture leans into Orleans' strengths rather than fighting them with HTTP boundaries between services. Grain-to-grain communication within a single cluster is sub-millisecond and avoids the serialisation overhead of cross-service HTTP calls, making it the natural fit for the tightly coupled flows of seat reservation, order creation and payment confirmation.

There are two discrete runtime components and a shared library:

- **Gateway** — A thin, stateless ASP.NET Core API sitting behind Azure Front Door. Handles request validation before forwarding calls into the Orleans cluster as a client. Scales horizontally with no state.
- **Silo** — The Orleans silo hosting all grain implementations. Co-hosts ASP.NET Core for health checks and diagnostics but does not serve public traffic. Scales based on grain count and CPU utilisation.
- **Shared** — A class library containing grain interfaces, shared DTOs and constants, referenced by both the Gateway and Silo projects.

#### Grain Design

Orleans guarantees single-threaded execution per grain, eliminating the need for distributed locks or optimistic concurrency conflicts. The grain topology is designed to maximise parallelism across high-contention paths:

- **EventGrain** (one per event) — Holds event metadata: name, venue, dates, sale categories. Low contention; only admins write to it.
- **SectionGrain** (one per event × section) — Owns the seat availability bitmap for its section. A 20,000-seat arena with ~30 sections yields 30-way parallelism for concurrent seat operations, avoiding a single-grain bottleneck.
- **OrderGrain** (one per order) — A state machine (`Created → SeatsHeld → PaymentProcessing → Confirmed/Failed`). Uses Orleans reminders for expiry; if payment doesn't complete within a configured window the grain releases its held seats and cancels the order, replacing the need for an external saga orchestrator.
- **UserGrain** (one per user) — Profile data and order history references. Keeps the user's active session cached in-memory to avoid unnecessary database queries.

#### Purchase Flow

1. The user reserves a seat via the Gateway, which calls `SectionGrain.ReserveAsync`.
2. The SectionGrain checks its bitmap, marks the seat as held and returns success or failure.
3. The Gateway creates an `OrderGrain`, which transitions to `SeatsHeld` and registers an expiry reminder.
4. On payment, the OrderGrain calls the payment provider, then makes grain-to-grain calls to `SectionGrain.ConfirmSeatAsync` and `UserGrain.AddOrderAsync` — no HTTP, no serialisation, just in-memory routing within the cluster.

---

### Infrastructure

All infrastructure is defined in Bicep, modularised under `infra/` with a single `main.bicep` entry point composing discrete modules for networking, compute, data and edge.

![Infrastructure Topology](assets/topology.png)

##### Networking

A `/14` VNet is partitioned into dedicated subnets: one per AKS node pool (system, gateway, silo), a shared private endpoint subnet for all PaaS services (Cosmos DB, Key Vault), and a Private Link Service subnet for Front Door ingress. Private DNS zones for `privatelink.documents.azure.com` and `privatelink.vaultcore.azure.net` are linked to the VNet, ensuring all PaaS traffic resolves over the private backbone. No public endpoints are exposed on any backing service.

##### Compute — AKS

A single AKS cluster hosts one system node pool on the `aks-system` VNet subnet:

- **System** (`Standard_D2s_v6`, 2–5 nodes) — Runs all workloads including the Orleans Silo deployment. Azure CNI networking, autoscaling enabled.

The VNet also reserves `aks-gateway` and `aks-silo` subnets for future dedicated workload pools. Workload identity and OIDC issuer are enabled for keyless AAD authentication to Azure services (Cosmos DB). The cluster auto-upgrades on the `stable` channel.

##### Data — CosmosDB

A provisioned-autoscale CosmosDB account (1,000 RU/s max, Session consistency) in northeurope hosts the `alwayson` database with three containers:

- `orleans-clustering` (partitioned on `/ClusterId`) — Silo membership table.
- `orleans-grain-state` (partitioned on `/PartitionKey`) — Persistent grain state.
- `orleans-reminders` (partitioned on `/PartitionKey`) — Reminder registrations.

The account is accessible only via a private endpoint in the shared PE subnet; public network access is disabled entirely. Local (key-based) auth is disabled — the Silo authenticates using `DefaultAzureCredential` via a User-Assigned Managed Identity with the Cosmos DB Built-in Data Contributor role, federated to the `silo-sa` Kubernetes service account through AKS workload identity. Automatic failover is enabled.

##### Secrets — Key Vault

A Standard-tier Key Vault is deployed with RBAC authorisation, soft delete (90-day retention) and no public network access via a private endpoint in the shared PE subnet. No connection strings are stored in application configuration — Cosmos access uses AAD tokens via workload identity.

##### Edge — Azure Front Door

Azure Front Door Premium acts as the global entry point, terminating TLS and routing traffic to the AKS internal load balancer via Private Link Service. A WAF policy runs in Prevention mode with Microsoft Default Rule Set 2.1 and Bot Manager Rule Set 1.1. A custom rate-limit rule caps requests at 1,000 per minute per client IP. Front Door is the only publicly exposed resource — all backend traffic flows over the Azure private backbone.

---

### Benchmarks

