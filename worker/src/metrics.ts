type CounterMap = Record<string, number>
type GaugeMap = Record<string, number>

const counters: CounterMap = {}
const gauges: GaugeMap = {}

const help: Record<string, string> = {
  worker_inbox_put_total: 'Inbox items stored',
  worker_inbox_get_total: 'Inbox items fetched',
  worker_inbox_replay_total: 'Inbox replay attempts blocked',
  worker_inbox_expired_total: 'Inbox items expired by janitor',
  worker_forget_deleted_total: 'Inbox entries deleted via forget',
  worker_forget_replay_deleted_total: 'Replay keys deleted via forget',
  worker_rate_limit_blocked_total: 'Requests blocked by inbox rate-limit',
  worker_notify_rate_blocked_total: 'Notify requests blocked',
  worker_notify_sent_total: 'Notify deliveries accepted',
  worker_notify_retry_total: 'Notify retries attempted',
  worker_notify_failed_total: 'Notify deliveries failed after retries',
  worker_notify_breaker_blocked_total: 'Notify breaker open (blocked)',
  worker_notify_breaker_open_total: 'Notify breaker trips',
  worker_notify_deduped_total: 'Notify deduped by hash',
  worker_metrics_auth_blocked_total: 'Metrics requests unauthorized',
}

const types: Record<string, 'counter' | 'gauge'> = {}
Object.keys(help).forEach((k) => { types[k] = 'counter' })

function norm(name: string) { return name.replace(/[^A-Za-z0-9_]/g, '_') }

export function inc(name: string, value = 1) {
  const k = norm(name)
  counters[k] = (counters[k] || 0) + value
}

export function gauge(name: string, value: number) {
  gauges[norm(name)] = value
}

export function toProm(): string {
  const lines: string[] = []
  Object.entries(help).forEach(([k, v]) => {
    lines.push(`# HELP ${k} ${v}`)
    lines.push(`# TYPE ${k} ${types[k]}`)
  })
  Object.entries(counters).forEach(([k, v]) => lines.push(`${k} ${v}`))
  Object.entries(gauges).forEach(([k, v]) => lines.push(`${k} ${v}`))
  return lines.join('\n') + '\n'
}

export function resetAll() {
  Object.keys(counters).forEach((k) => delete counters[k])
  Object.keys(gauges).forEach((k) => delete gauges[k])
}
