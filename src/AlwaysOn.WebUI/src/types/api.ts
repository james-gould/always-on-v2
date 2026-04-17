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
