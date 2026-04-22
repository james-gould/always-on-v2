import type {
  EventDetails,
  CreateEventRequest,
  OrderDetails,
  CreateOrderRequest,
  CreateOrderResponse,
  TicketDetails,
  QueueEntry,
} from '@/types/api'

const BASE = '/api'

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${url}`, {
    headers: { 'Content-Type': 'application/json', ...init?.headers },
    ...init,
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`API ${res.status}: ${body}`)
  }
  return res.json() as Promise<T>
}

export const api = {
  events: {
    get: (eventId: string) => request<EventDetails>(`/events/${eventId}`),
    create: (body: CreateEventRequest) =>
      request<EventDetails>('/events', { method: 'POST', body: JSON.stringify(body) }),
  },
  orders: {
    get: (orderId: string) => request<OrderDetails>(`/orders/${orderId}`),
    create: (body: CreateOrderRequest) =>
      request<CreateOrderResponse>('/orders', { method: 'POST', body: JSON.stringify(body) }),
  },
  tickets: {
    get: (ticketId: string) => request<TicketDetails>(`/tickets/${ticketId}`),
  },
  queue: {
    enqueue: (eventId: string, userId: string) =>
      request<QueueEntry>(`/events/${eventId}/queue`, {
        method: 'POST',
        body: JSON.stringify({ userId }),
      }),
    my: (queueId: string) => request<QueueEntry>(`/myqueue/${queueId}`),
    release: (queueId: string, completed: boolean) =>
      request<QueueEntry>(`/myqueue/${queueId}/release`, {
        method: 'POST',
        body: JSON.stringify({ completed }),
      }),
  },
}
