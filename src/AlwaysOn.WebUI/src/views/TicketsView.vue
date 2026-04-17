<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/services/api'
import type { EventDetails } from '@/types/api'

const route = useRoute()
const router = useRouter()
const eventId = route.params.eventId as string

const event = ref<EventDetails | null>(null)
const quantity = ref(1)
const error = ref('')

onMounted(async () => {
  try {
    event.value = await api.events.get(eventId)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Event not found'
  }
})

function placeOrder() {
  router.push({
    name: 'order',
    params: { eventId },
    query: { qty: String(quantity.value) },
  })
}
</script>

<template>
  <div class="tickets-view">
    <h1>Select Tickets</h1>
    <p v-if="error" class="error">{{ error }}</p>

    <template v-if="event">
      <h2>{{ event.name }}</h2>
      <p>{{ event.venue }} — {{ new Date(event.startsAtUtc).toLocaleString() }}</p>

      <label>
        How many tickets?
        <input v-model.number="quantity" type="number" min="1" :max="event.capacity" />
      </label>

      <button class="primary" :disabled="quantity < 1" @click="placeOrder">Place Order</button>
    </template>
  </div>
</template>

<style scoped>
.tickets-view {
  max-width: 500px;
  margin: 0 auto;
  padding: 2rem;
}
label {
  display: block;
  margin: 1.5rem 0 1rem;
}
label input {
  display: block;
  width: 100%;
  margin-top: 0.25rem;
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
button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
