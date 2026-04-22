<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { HubConnectionBuilder, HubConnectionState, type HubConnection } from '@microsoft/signalr'
import { api } from '@/services/api'
import { getOrCreateUserId } from '@/services/user'
import {
  QueueEntryStatus,
  type EventDetails,
  type QueueEntry,
  type ReservationReadyPayload,
} from '@/types/api'

const route = useRoute()
const router = useRouter()
const eventId = route.params.eventId as string
const userId = getOrCreateUserId()

const eventDetails = ref<EventDetails | null>(null)
const queueEntry = ref<QueueEntry | null>(null)
const error = ref('')
const countdownSeconds = ref<number | null>(null)

let pollTimer: ReturnType<typeof setInterval> | undefined
let countdownTimer: ReturnType<typeof setInterval> | undefined
let hub: HubConnection | undefined

function stopTimers() {
  if (pollTimer) clearInterval(pollTimer)
  if (countdownTimer) clearInterval(countdownTimer)
  pollTimer = undefined
  countdownTimer = undefined
}

function applyEntry(entry: QueueEntry) {
  queueEntry.value = entry
  if (entry.status === QueueEntryStatus.Ready && entry.reservationExpiresAtUtc) {
    startCountdown(entry.reservationExpiresAtUtc)
  } else if (entry.status !== QueueEntryStatus.Ready) {
    countdownSeconds.value = null
    if (countdownTimer) {
      clearInterval(countdownTimer)
      countdownTimer = undefined
    }
  }
}

function startCountdown(expiresAtUtc: string) {
  const expires = new Date(expiresAtUtc).getTime()
  const tick = () => {
    const remaining = Math.max(0, Math.round((expires - Date.now()) / 1000))
    countdownSeconds.value = remaining
    if (remaining <= 0 && countdownTimer) {
      clearInterval(countdownTimer)
      countdownTimer = undefined
    }
  }
  tick()
  if (countdownTimer) clearInterval(countdownTimer)
  countdownTimer = setInterval(tick, 1000)
}

async function pollOnce() {
  if (!queueEntry.value) return
  try {
    const latest = await api.queue.my(queueEntry.value.queueId)
    applyEntry(latest)
  } catch {
    // Transient; next poll will retry.
  }
}

async function connectHub() {
  const connection = new HubConnectionBuilder()
    .withUrl('/hubs/queue')
    .withAutomaticReconnect()
    .build()

  connection.on('ReservationReady', async (payload: ReservationReadyPayload) => {
    if (payload.eventId !== eventId) return
    // Refresh from /myqueue to pick up the Ready state + position=0.
    await pollOnce()
  })

  await connection.start()
  await connection.invoke('SubscribeAsync', userId)
  hub = connection
}

onMounted(async () => {
  try {
    eventDetails.value = await api.events.get(eventId)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Event not found'
    return
  }

  try {
    const entry = await api.queue.enqueue(eventId, userId)
    applyEntry(entry)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Failed to join queue'
    return
  }

  // SignalR gives instant promotion; polling is the fallback for dropped WS.
  try {
    await connectHub()
  } catch {
    // Polling alone will still surface promotion within ~2s.
  }

  pollTimer = setInterval(pollOnce, 2000)
})

onUnmounted(async () => {
  stopTimers()
  if (hub && hub.state !== HubConnectionState.Disconnected) {
    try {
      await hub.stop()
    } catch {
      /* ignore */
    }
  }
})

async function proceed() {
  if (!queueEntry.value) return
  try {
    await api.queue.release(queueEntry.value.queueId, true)
  } catch {
    // Non-fatal — slot will reclaim on the 3-minute reservation timeout.
  }
  router.push({ name: 'tickets', params: { eventId } })
}
</script>

<template>
  <div class="queue-view">
    <h1>Queue</h1>
    <p v-if="error" class="error">{{ error }}</p>

    <template v-if="eventDetails && queueEntry">
      <h2>{{ eventDetails.name }}</h2>

      <div v-if="queueEntry.status === QueueEntryStatus.Waiting" class="waiting">
        <div class="spinner" />
        <p>Your position in queue: <strong>{{ queueEntry.position }}</strong></p>
        <p class="hint">Please wait — you'll be let through shortly.</p>
      </div>

      <div v-else-if="queueEntry.status === QueueEntryStatus.Ready" class="ready">
        <p>You're in! You have
          <strong v-if="countdownSeconds !== null">{{ countdownSeconds }}s</strong>
          <strong v-else>3 minutes</strong>
          to complete your purchase.
        </p>
        <button class="primary" @click="proceed">Select Tickets</button>
      </div>

      <div v-else-if="queueEntry.status === QueueEntryStatus.Expired" class="expired">
        <p>Your reservation window expired. Please re-join the queue to try again.</p>
      </div>

      <div v-else-if="queueEntry.status === QueueEntryStatus.Completed" class="ready">
        <p>Reservation released. Good luck with your tickets!</p>
      </div>
    </template>
  </div>
</template>

<style scoped>
.queue-view {
  max-width: 500px;
  margin: 0 auto;
  padding: 2rem;
  text-align: center;
}
.waiting {
  margin-top: 2rem;
}
.spinner {
  width: 48px;
  height: 48px;
  border: 4px solid #e5e7eb;
  border-top-color: #10b981;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
  margin: 0 auto 1rem;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.hint {
  color: #6b7280;
  font-size: 0.875rem;
}
.ready,
.expired {
  margin-top: 2rem;
}
.expired {
  color: #b45309;
}
.error {
  color: #e53e3e;
}
button.primary {
  padding: 0.75rem 1.5rem;
  background: #10b981;
  color: #fff;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 1rem;
}
</style>
