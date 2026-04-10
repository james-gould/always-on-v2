A ramp-up project for Senior Software Engineers at Microsoft, architecturing a globally scalable low-latency API utilising:

- Orleans
- AKS (Kubernetes)
- CosmosDB
- Azure Key Vault
- ASP.NET Core 10
- Bicep for IaC

---

### Application Layer

The scenario being scaled is a replica of Ticketmaster, the distribution of events with tickets purchasable globally. Atomic purchases of specific seats, allocation of categorised sales (pre-sale, early bird, general admission etc) and event history offers a breadth of functionality to demonstrate the utility of the tech stack.

The architecture leans into Orleans' strengths rather than fighting them with HTTP boundaries between services. Grain-to-grain communication within a single cluster is sub-millisecond and avoids the serialisation overhead of cross-service HTTP calls, making it the natural fit for the tightly coupled flows of seat reservation, order creation and payment confirmation.

There are two discrete runtime components and a shared library:

- **Gateway** — A thin, stateless ASP.NET Core API sitting behind Azure Front Door. Handles request validation before forwarding calls into the Orleans cluster as a client. Scales horizontally with no state.
- **Silo** — The Orleans silo hosting all grain implementations. Co-hosts ASP.NET Core for health checks and diagnostics but does not serve public traffic. Scales based on grain count and CPU utilisation.
- **Abstractions** — A class library containing grain interfaces and shared DTOs, referenced by both the Gateway and Silo projects.

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

##### Networking

A `/14` VNet is partitioned into dedicated subnets: one per AKS node pool (system, gateway, silo) and two for private endpoints (CosmosDB, Key Vault). Private DNS zones for `privatelink.documents.azure.com` and `privatelink.vaultcore.azure.net` are linked to the VNet, ensuring all PaaS traffic resolves over the private backbone. No public endpoints are exposed on any backing service.

##### Compute — AKS

A single AKS cluster hosts three node pools:

- **System** (`Standard_D2s_v5`, 2–4 nodes) — Tainted for critical add-ons only; runs CoreDNS, kube-proxy and the secrets store CSI driver.
- **Gateway** (`Standard_D4s_v5`, 2–20 nodes) — General-purpose pool for the stateless Gateway `Deployment`, autoscaling on CPU and request count.
- **Silo** (`Standard_E4s_v5`, 3–15 nodes) — Memory-optimised pool for the Orleans `StatefulSet`, providing stable network identities required for cluster membership.

All pools are spread across availability zones 1, 2 and 3 for zone-redundant resilience. Workload identity and OIDC issuer are enabled for keyless authentication to Azure services. The Key Vault secrets provider CSI driver rotates secrets on a two-minute polling interval. Cilium is configured as both the network plugin and policy engine. Container Insights ships logs and metrics to a Log Analytics workspace with a 30-day retention.

##### Data — CosmosDB

A serverless CosmosDB account with Session consistency hosts the `Orleans` database, pre-provisioned with three containers:

- `OrleansCluster` (partitioned on `/ClusterId`) — Silo membership table.
- `OrleansGrainState` (partitioned on `/PartitionKey`) — Persistent grain state.
- `OrleansReminders` (partitioned on `/PartitionKey`) — Reminder registrations.

The account is accessible only via a private endpoint in the VNet; public network access is disabled entirely. Automatic failover and zone redundancy are enabled.

##### Secrets — Key Vault

A Standard-tier Key Vault is deployed with RBAC authorisation, soft delete (90-day retention) and no public network access. AKS workloads access secrets through the CSI driver using workload identity; no connection strings are stored in application configuration.

##### Edge — Azure Front Door

Azure Front Door Premium acts as the global entry point, terminating TLS and routing traffic to the Gateway ingress. A WAF policy runs in Prevention mode with Microsoft Default Rule Set 2.1 and Bot Manager Rule Set 1.1. A custom rate-limit rule caps requests at 1,000 per minute per client IP.

--- 