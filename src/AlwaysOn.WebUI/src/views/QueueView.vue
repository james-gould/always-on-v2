<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/services/api'
import type { EventDetails } from '@/types/api'

const route = useRoute()
const router = useRouter()
const eventId = route.params.eventId as string

const event = ref<EventDetails | null>(null)
const position = ref(0)
const waiting = ref(true)
const error = ref('')

let timer: ReturnType<typeof setInterval> | undefined

onMounted(async () => {
  try {
    event.value = await api.events.get(eventId)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Event not found'
    return
  }

  // Simulate a queue countdown
  position.value = Math.floor(Math.random() * 50) + 5
  timer = setInterval(() => {
    position.value = Math.max(0, position.value - Math.floor(Math.random() * 3 + 1))
    if (position.value <= 0) {
      waiting.value = false
      if (timer) clearInterval(timer)
    }
  }, 800)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})

function proceed() {
  router.push({ name: 'tickets', params: { eventId } })
}
</script>

<template>
  <div class="queue-view">
    <h1>Queue</h1>
    <p v-if="error" class="error">{{ error }}</p>

    <template v-if="event">
      <h2>{{ event.name }}</h2>

      <div v-if="waiting" class="waiting">
        <div class="spinner" />
        <p>Your position in queue: <strong>{{ position }}</strong></p>
        <p class="hint">Please wait — you'll be let through shortly.</p>
      </div>

      <div v-else class="ready">
        <p>You're in! Choose your tickets.</p>
        <button class="primary" @click="proceed">Select Tickets</button>
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
.ready {
  margin-top: 2rem;
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
