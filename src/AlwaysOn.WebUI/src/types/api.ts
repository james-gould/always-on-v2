export interface EventDetails {
  eventId: string
  name: string
  startsAtUtc: string
  venue: string
  capacity: number
}

export interface OrderDetails {
  orderId: string
  eventId: string
  userId: string
  status: string
  createdAtUtc: string
  ticketIds: string[]
}

export interface TicketDetails {
  ticketId: string
  eventId: string
  orderId: string
  userId: string
  status: string
  issuedAtUtc: string
}

export interface CreateEventRequest {
  eventId?: string
  name: string
  startsAtUtc: string
  venue: string
  capacity: number
}

export interface CreateOrderRequest {
  orderId?: string
  eventId: string
  userId: string
  ticketQuantity: number
}

export interface CreateOrderResponse {
  order: OrderDetails
  tickets: TicketDetails[]
}

export interface IssueTicketRequest {
  ticketId?: string
  eventId: string
  orderId: string
  userId: string
}

export enum QueueEntryStatus {
  Waiting = 0,
  Ready = 1,
  Expired = 2,
  Completed = 3,
}

export interface QueueEntry {
  queueId: string
  eventId: string
  userId: string
  enqueuedAtUtc: string
  status: QueueEntryStatus
  position: number
  eventName: string | null
  reservationExpiresAtUtc: string | null
}

export interface ReservationReadyPayload {
  queueId: string
  eventId: string
  userId: string
  reservationExpiresAtUtc: string
}
