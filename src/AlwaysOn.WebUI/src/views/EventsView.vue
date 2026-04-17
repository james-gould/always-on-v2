<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/services/api'
import type { EventDetails, CreateEventRequest } from '@/types/api'

const router = useRouter()
const eventId = ref('')
const event = ref<EventDetails | null>(null)
const error = ref('')
const showCreate = ref(false)

const form = ref<CreateEventRequest>({
  name: '',
  startsAtUtc: '',
  venue: '',
  capacity: 1000,
})

async function lookupEvent() {
  error.value = ''
  event.value = null
  if (!eventId.value.trim()) return
  try {
    event.value = await api.events.get(eventId.value.trim())
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Failed to fetch event'
  }
}

async function createEvent() {
  error.value = ''
  try {
    const created = await api.events.create({
      ...form.value,
      startsAtUtc: new Date(form.value.startsAtUtc).toISOString(),
    })
    event.value = created
    eventId.value = created.eventId
    showCreate.value = false
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : 'Failed to create event'
  }
}

function enterQueue() {
  if (event.value) {
    router.push({ name: 'queue', params: { eventId: event.value.eventId } })
  }
}
</script>

<template>
  <div class="events-view">
    <h1>Event Dashboard</h1>

    <section class="lookup">
      <h2>Find an Event</h2>
      <div class="input-group">
        <input v-model="eventId" placeholder="Enter Event ID" @keyup.enter="lookupEvent" />
        <button @click="lookupEvent">Look up</button>
      </div>
    </section>

    <p v-if="error" class="error">{{ error }}</p>

    <section v-if="event" class="event-card">
      <h2>{{ event.name }}</h2>
      <dl>
        <dt>Event ID</dt>
        <dd>{{ event.eventId }}</dd>
        <dt>Venue</dt>
        <dd>{{ event.venue }}</dd>
        <dt>Starts</dt>
        <dd>{{ new Date(event.startsAtUtc).toLocaleString() }}</dd>
        <dt>Capacity</dt>
        <dd>{{ event.capacity }}</dd>
      </dl>
      <button class="primary" @click="enterQueue">Enter Queue</button>
    </section>

    <hr />

    <button @click="showCreate = !showCreate">
      {{ showCreate ? 'Cancel' : '+ Create Event' }}
    </button>

    <section v-if="showCreate" class="create-form">
      <h2>Create Event</h2>
      <label>
        Name
        <input v-model="form.name" />
      </label>
      <label>
        Venue
        <input v-model="form.venue" />
      </label>
      <label>
        Starts at
        <input v-model="form.startsAtUtc" type="datetime-local" />
      </label>
      <label>
        Capacity
        <input v-model.number="form.capacity" type="number" min="1" />
      </label>
      <button class="primary" @click="createEvent">Create</button>
    </section>
  </div>
</template>

<style scoped>
.events-view {
  max-width: 600px;
  margin: 0 auto;
  padding: 2rem;
}
.input-group {
  display: flex;
  gap: 0.5rem;
}
.input-group input {
  flex: 1;
}
.event-card {
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
.create-form {
  margin-top: 1rem;
}
.create-form label {
  display: block;
  margin-bottom: 0.75rem;
}
.create-form input {
  display: block;
  width: 100%;
  margin-top: 0.25rem;
}
.error {
  color: #e53e3e;
}
button {
  padding: 0.5rem 1rem;
  cursor: pointer;
  border: 1px solid var(--color-border, #ccc);
  border-radius: 4px;
  background: transparent;
}
button.primary {
  background: #10b981;
  color: #fff;
  border-color: #10b981;
}
</style>
