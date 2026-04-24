<#
.SYNOPSIS
    Interactive demo script for the AlwaysOn solution.

.DESCRIPTION
    Walks through the core API flows against the live Azure deployment:
      1) Create an event
      2) Place orders + issue tickets
      3) Join the reservation queue
      4) Load test with hey (if installed)
      5) Show live pod + Redis metrics

    Designed for a live presentation — each section pauses for narration.

.PARAMETER BaseUrl
    The AFD endpoint URL. Defaults to the dev environment.

.PARAMETER SkipLoadTest
    Skip the hey load test section.

.EXAMPLE
    .\Demo-AlwaysOn.ps1
    .\Demo-AlwaysOn.ps1 -BaseUrl "https://my-custom-endpoint.azurefd.net"
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = "https://alwayson-dev-endpoint-h9ckhvhgfwgagtas.b01.azurefd.net",
    [switch]$SkipLoadTest
)

$ErrorActionPreference = 'Continue'

# ── Helpers ────────────────────────────────────────────────────
function Write-Section([string]$title) {
    Write-Host ""
    Write-Host ("━" * 60) -ForegroundColor DarkGray
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host ("━" * 60) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Metric([string]$label, [string]$value, [string]$color = "Yellow") {
    Write-Host "  $($label.PadRight(22))" -NoNewline -ForegroundColor Gray
    Write-Host $value -ForegroundColor $color
}

function Invoke-Api {
    param(
        [string]$Method = "GET",
        [string]$Path,
        [object]$Body,
        [switch]$Silent
    )
    $uri = "$BaseUrl$Path"
    $params = @{ Uri = $uri; Method = $Method; ContentType = "application/json"; UseBasicParsing = $true }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 5) }

    $time = Measure-Command {
        $resp = Invoke-WebRequest @params -SkipHttpErrorCheck
    }

    $result = [PSCustomObject]@{
        Status   = $resp.StatusCode
        TimeMs   = [int]$time.TotalMilliseconds
        Body     = if ($resp.Content) { $resp.Content | ConvertFrom-Json } else { $null }
        RawBody  = $resp.Content
    }

    if (-not $Silent) {
        $statusColor = if ($result.Status -ge 200 -and $result.Status -lt 300) { "Green" } else { "Red" }
        Write-Host "  $Method $Path" -NoNewline -ForegroundColor White
        Write-Host " → " -NoNewline
        Write-Host "$($result.Status)" -NoNewline -ForegroundColor $statusColor
        Write-Host " ($($result.TimeMs)ms)" -ForegroundColor DarkGray
    }

    return $result
}

function Pause-ForNarration([string]$hint = "Press Enter to continue...") {
    Write-Host ""
    Write-Host "  $hint" -ForegroundColor DarkYellow
    Read-Host | Out-Null
}

# ── Banner ─────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "   █████╗ ██╗    ██╗    ██╗ █████╗ ██╗   ██╗███████╗" -ForegroundColor Blue
Write-Host "  ██╔══██╗██║    ██║    ██║██╔══██╗╚██╗ ██╔╝██╔════╝" -ForegroundColor Blue
Write-Host "  ███████║██║    ██║ █╗ ██║███████║ ╚████╔╝ ███████╗" -ForegroundColor Blue
Write-Host "  ██╔══██║██║    ██║███╗██║██╔══██║  ╚██╔╝  ╚════██║" -ForegroundColor Blue
Write-Host "  ██║  ██║███████╗╚███╔███╔╝██║  ██║   ██║   ███████║" -ForegroundColor Blue
Write-Host "  ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝" -ForegroundColor Blue
Write-Host "                 ON" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Orleans 10 · AKS · Cosmos DB · Redis · Azure Front Door" -ForegroundColor DarkGray
Write-Host "  Endpoint: $BaseUrl" -ForegroundColor DarkGray
Write-Host ""

Pause-ForNarration "Press Enter to start the demo..."

# ══════════════════════════════════════════════════════════════
# 1. HEALTH CHECK
# ══════════════════════════════════════════════════════════════
Write-Section "1 · Health Check"
Write-Host "  Verifying the silo is alive through Azure Front Door..." -ForegroundColor Gray
$health = Invoke-Api -Path "/alive"
if ($health.Status -eq 200) {
    Write-Host "  ✓ Silo is healthy" -ForegroundColor Green
} else {
    Write-Host "  ✗ Silo returned $($health.Status) — check the deployment" -ForegroundColor Red
}

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 2. CREATE AN EVENT
# ══════════════════════════════════════════════════════════════
Write-Section "2 · Create an Event"
Write-Host "  Creating a concert event with 10,000 capacity..." -ForegroundColor Gray

$eventId = "demo-event-$(Get-Date -Format 'HHmmss')"
$event = Invoke-Api -Method POST -Path "/events" -Body @{
    eventId     = $eventId
    name        = "Orleans Summit 2026"
    startsAtUtc = (Get-Date).AddDays(30).ToUniversalTime().ToString("o")
    venue       = "Microsoft Theater, Los Angeles"
    capacity    = 10000
}

if ($event.Body) {
    Write-Host ""
    Write-Metric "Event ID"     $event.Body.eventId
    Write-Metric "Name"         $event.Body.name
    Write-Metric "Venue"        $event.Body.venue
    Write-Metric "Capacity"     $event.Body.capacity
    Write-Metric "Starts"       $event.Body.startsAtUtc
}

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 3. READ IT BACK (Redis cache path)
# ══════════════════════════════════════════════════════════════
Write-Section "3 · Read Event (Redis Cache Path)"
Write-Host "  First read populates the Redis cache, second is a cache hit..." -ForegroundColor Gray
Write-Host ""

$r1 = Invoke-Api -Path "/events/$eventId"
$r2 = Invoke-Api -Path "/events/$eventId"
$r3 = Invoke-Api -Path "/events/$eventId"

Write-Host ""
Write-Metric "1st read (cache miss)" "$($r1.TimeMs)ms"
Write-Metric "2nd read (cache hit)"  "$($r2.TimeMs)ms" "Green"
Write-Metric "3rd read (cache hit)"  "$($r3.TimeMs)ms" "Green"

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 4. PLACE ORDERS
# ══════════════════════════════════════════════════════════════
Write-Section "4 · Place Orders + Issue Tickets"
Write-Host "  Creating 5 orders with 2 tickets each (10 tickets total)..." -ForegroundColor Gray
Write-Host ""

$orderTimes = @()
for ($i = 1; $i -le 5; $i++) {
    $order = Invoke-Api -Method POST -Path "/orders" -Body @{
        eventId        = $eventId
        userId         = "user-$i"
        ticketQuantity = 2
    }
    $orderTimes += $order.TimeMs

    if ($order.Body -and $order.Body.order) {
        $ticketCount = ($order.Body.tickets | Measure-Object).Count
        Write-Host "    → Order $($order.Body.order.orderId): $ticketCount tickets, status=$($order.Body.order.status)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Metric "Avg order time" "$([int]($orderTimes | Measure-Object -Average).Average)ms"
Write-Metric "Min"            "$($orderTimes | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum)ms" "Green"
Write-Metric "Max"            "$($orderTimes | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)ms"

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 5. RESERVATION QUEUE
# ══════════════════════════════════════════════════════════════
Write-Section "5 · Reservation Queue (Event Grid + Redis)"
Write-Host "  Enqueuing 3 users into the reservation queue..." -ForegroundColor Gray
Write-Host ""

$queueIds = @()
for ($i = 1; $i -le 3; $i++) {
    $enqueue = Invoke-Api -Method POST -Path "/events/$eventId/queue" -Body @{
        userId = "queue-user-$i"
    }
    if ($enqueue.Body) {
        $queueIds += $enqueue.Body.queueId
        Write-Host "    → User queue-user-$i: position=$($enqueue.Body.position), status=$($enqueue.Body.status)" -ForegroundColor DarkGray
    }
}

if ($queueIds.Count -gt 0) {
    Write-Host ""
    Write-Host "  Checking queue position from Redis mirror..." -ForegroundColor Gray
    $queueCheck = Invoke-Api -Path "/myqueue/$($queueIds[0])"
    if ($queueCheck.Body) {
        Write-Metric "Queue ID"  $queueCheck.Body.queueId
        Write-Metric "Status"    $queueCheck.Body.status
        Write-Metric "Position"  $queueCheck.Body.position
    }
}

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 6. BURST READ TEST
# ══════════════════════════════════════════════════════════════
Write-Section "6 · Burst Read Test (50 sequential requests)"
Write-Host "  Hammering GET /events/$eventId to show Redis cache performance..." -ForegroundColor Gray
Write-Host ""

$burstTimes = 1..50 | ForEach-Object {
    $t = Measure-Command {
        Invoke-WebRequest -Uri "$BaseUrl/events/$eventId" -UseBasicParsing -SkipHttpErrorCheck | Out-Null
    }
    [int]$t.TotalMilliseconds
}

$stats = $burstTimes | Measure-Object -Average -Minimum -Maximum
$p50 = ($burstTimes | Sort-Object)[24]
$p99 = ($burstTimes | Sort-Object)[48]

Write-Metric "Requests"  "50"
Write-Metric "Avg"       "$([int]$stats.Average)ms"
Write-Metric "Min"       "$($stats.Minimum)ms" "Green"
Write-Metric "Max"       "$($stats.Maximum)ms"
Write-Metric "P50"       "${p50}ms" "Green"
Write-Metric "P99"       "${p99}ms"

# Simple ASCII histogram
Write-Host ""
Write-Host "  Latency distribution:" -ForegroundColor Gray
$buckets = @(
    @{ Label = "  <50ms "; Max = 50 }
    @{ Label = " <100ms "; Max = 100 }
    @{ Label = " <200ms "; Max = 200 }
    @{ Label = " <500ms "; Max = 500 }
    @{ Label = "  500ms+"; Max = [int]::MaxValue }
)
$prev = 0
foreach ($b in $buckets) {
    $count = ($burstTimes | Where-Object { $_ -ge $prev -and $_ -lt $b.Max }).Count
    $bar = "█" * [Math]::Min($count, 40)
    $padLabel = $b.Label
    Write-Host "    $padLabel " -NoNewline -ForegroundColor Gray
    Write-Host "$bar" -NoNewline -ForegroundColor Blue
    Write-Host " $count" -ForegroundColor DarkGray
    $prev = $b.Max
}

Pause-ForNarration

# ══════════════════════════════════════════════════════════════
# 7. LOAD TEST (hey)
# ══════════════════════════════════════════════════════════════
if (-not $SkipLoadTest) {
    Write-Section "7 · Load Test (10,000 requests / 500 concurrent)"

    if (Get-Command hey -ErrorAction SilentlyContinue) {
        Write-Host "  Running: hey -n 10000 -c 500 $BaseUrl/events/$eventId" -ForegroundColor Gray
        Write-Host ""
        hey -n 10000 -c 500 "$BaseUrl/events/$eventId"
    } else {
        Write-Host "  'hey' is not installed. Install with: go install github.com/rakyll/hey@latest" -ForegroundColor Yellow
        Write-Host "  Skipping load test." -ForegroundColor DarkGray
    }

    Pause-ForNarration
}

# ══════════════════════════════════════════════════════════════
# 8. INFRASTRUCTURE METRICS
# ══════════════════════════════════════════════════════════════
Write-Section "8 · Infrastructure Snapshot"

if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host "  Pod status:" -ForegroundColor Gray
    kubectl get pods -l app.kubernetes.io/component=silo -o wide 2>$null
    Write-Host ""

    Write-Host "  Node resources:" -ForegroundColor Gray
    kubectl top nodes 2>$null
    Write-Host ""

    Write-Host "  Pod resources:" -ForegroundColor Gray
    kubectl top pods -l app.kubernetes.io/component=silo 2>$null
} else {
    Write-Host "  kubectl not available — skipping cluster metrics." -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────
Write-Host ""
Write-Host ("━" * 60) -ForegroundColor DarkGray
Write-Host "  Demo complete." -ForegroundColor Green
Write-Host ("━" * 60) -ForegroundColor DarkGray
Write-Host ""
