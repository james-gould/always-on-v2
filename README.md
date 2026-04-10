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

#### Infrastructure

A WAF (Azure Front Door) sits in front of all infrastructure with a public IP address, internally routing requests. The Gateway runs as a `Deployment` with a horizontal pod autoscaler on CPU and request count. The Silo runs as a `StatefulSet` with stable network identities (required for Orleans cluster membership), using CosmosDB for grain persistence and the membership table. Separate AKS node pools isolate the stateless Gateway tier from the memory-optimised Silo tier.