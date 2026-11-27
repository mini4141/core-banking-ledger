import http from 'k6/http'
import { check } from 'k6'
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js'

const ACCOUNTS = __ENV.ACCOUNTS_URL || 'http://localhost:8081'
const TRANSFER = __ENV.TRANSFER_URL || 'http://localhost:8082'
const POOL = Number(__ENV.ACCOUNT_POOL || 200)

export const options = {
  vus: Number(__ENV.VUS || 50),
  duration: __ENV.DURATION || '2m',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{name:transfer}': [`p(95)<${__ENV.P95_MS || 300}`],
  },
}

const json = { headers: { 'Content-Type': 'application/json' } }

export function setup() {
  const ids = []
  for (let i = 0; i < POOL; i++) {
    const created = http.post(`${ACCOUNTS}/accounts`, JSON.stringify({ customerName: `load-${i}`, currency: 'JPY' }), json)
    const id = created.json('id')
    http.post(`${ACCOUNTS}/accounts/${id}/deposit`, JSON.stringify({ amount: 100000000 }), json)
    ids.push(id)
  }
  return { ids }
}

export default function (data) {
  const n = data.ids.length
  const from = data.ids[Math.floor(Math.random() * n)]
  let to = data.ids[Math.floor(Math.random() * n)]
  if (to === from) to = data.ids[(data.ids.indexOf(from) + 1) % n]

  // balance reads exercise the Redis cache; a hot subset is read repeatedly
  http.get(`${ACCOUNTS}/accounts/${data.ids[Math.floor(Math.random() * 10)]}`, { tags: { name: 'balance' } })

  const key = `${__VU}-${__ITER}-${Date.now()}-${Math.random()}`
  const res = http.post(
    `${TRANSFER}/transfers`,
    JSON.stringify({ idempotencyKey: key, fromAccountId: from, toAccountId: to, amount: 100 }),
    { ...json, tags: { name: 'transfer' } },
  )
  check(res, { 'transfer 201': (r) => r.status === 201 })
}

export function handleSummary(data) {
  const out = {}
  out.stdout = textSummary(data, { indent: ' ', enableColors: false })
  if (__ENV.SUMMARY_OUT) out[__ENV.SUMMARY_OUT] = out.stdout
  return out
}
