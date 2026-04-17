<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/services/api'
import type { CreateOrderResponse } from '@/types/api'

const route = useRoute()
const router = useRouter()
const eventId = route.params.eventId as string
const quantity = Number(route.query.qty) || 1

const result = ref<CreateOrderResponse | null>(null)
const loading = ref(true)
const error = ref('')

onMounted(async () => {
  try {
    result.value = await api.orders.create({
      eventId,
      userId: 'user-' + crypto.randomUUID().slice(0, 8),
      ticketQuantity: quantity,
    })
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Order failed'
  } finally {
    loading.value = false
  }
})

function goHome() {
  router.push({ name: 'events' })
}
</script>

<template>
  <div class="order-view">
    <h1>Order Confirmation</h1>

    <div v-if="loading" class="loading">
      <div class="spinner" />
      <p>Placing your order...</p>
    </div>

    <p v-if="error" class="error">{{ error }}</p>

    <template v-if="result">
      <section class="order-card">
        <h2>Order {{ result.order.orderId }}</h2>
        <dl>
          <dt>Status</dt>
          <dd>{{ result.order.status }}</dd>
          <dt>Event</dt>
          <dd>{{ result.order.eventId }}</dd>
          <dt>Created</dt>
          <dd>{{ new Date(result.order.createdAtUtc).toLocaleString() }}</dd>
        </dl>
      </section>

      <section class="tickets">
        <h3>Tickets ({{ result.tickets.length }})</h3>
        <ul>
          <li v-for="ticket in result.tickets" :key="ticket.ticketId">
            <strong>{{ ticket.ticketId }}</strong> — {{ ticket.status }}
          </li>
        </ul>
      </section>

      <button class="primary" @click="goHome">Back to Events</button>
    </template>
  </div>
</template>

<style scoped>
.order-view {
  max-width: 600px;
  margin: 0 auto;
  padding: 2rem;
}
.loading {
  text-align: center;
  margin: 2rem 0;
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
.order-card {
  border: 1px solid var(--color-border, #ddd);
  border-radius: 8px;
  padding: 1.5rem;
  margin: 1rem 0;
}
dl {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.25rem 1rem;
}
dt {
  font-weight: 600;
}
.tickets {
  margin: 1.5rem 0;
}
.tickets ul {
  list-style: none;
  padding: 0;
}
.tickets li {
  padding: 0.5rem 0;
  border-bottom: 1px solid #e5e7eb;
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
