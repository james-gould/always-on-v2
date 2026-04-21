const STORAGE_KEY = 'alwayson.userId'

function generateId(): string {
  // crypto.randomUUID is available in modern browsers; hyphens stripped so the
  // value matches the Guid("N") format the backend uses everywhere else.
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID().replace(/-/g, '')
  }
  // Fallback for very old environments; good enough for an anonymous demo id.
  return Math.random().toString(36).slice(2) + Date.now().toString(36)
}

/**
 * Returns a stable anonymous user identifier for this browser profile.
 * The value persists in localStorage so reloads and multi-tab sessions
 * reuse the same id — used for queue identity and the per-user SignalR
 * notification channel.
 */
export function getOrCreateUserId(): string {
  try {
    const existing = localStorage.getItem(STORAGE_KEY)
    if (existing && existing.length > 0) {
      return existing
    }
    const created = generateId()
    localStorage.setItem(STORAGE_KEY, created)
    return created
  } catch {
    // localStorage may be unavailable (private mode); fall back to a volatile id.
    return generateId()
  }
}
