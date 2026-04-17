import { createRouter, createWebHistory } from 'vue-router'
import EventsView from '@/views/EventsView.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'events',
      component: EventsView,
    },
    {
      path: '/events/:eventId/queue',
      name: 'queue',
      component: () => import('@/views/QueueView.vue'),
    },
    {
      path: '/events/:eventId/tickets',
      name: 'tickets',
      component: () => import('@/views/TicketsView.vue'),
    },
    {
      path: '/events/:eventId/order',
      name: 'order',
      component: () => import('@/views/OrderView.vue'),
    },
  ],
})

export default router
