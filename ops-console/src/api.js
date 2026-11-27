async function call(path, options) {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  const text = await res.text()
  const body = text ? JSON.parse(text) : null
  return { ok: res.ok, status: res.status, body, replayed: res.headers.get('Idempotent-Replayed') === 'true' }
}

const post = (path, payload) => call(path, { method: 'POST', body: JSON.stringify(payload) })

export const api = {
  listAccounts: () => call('/api/accounts/accounts'),
  createAccount: (customerName, currency) => post('/api/accounts/accounts', { customerName, currency }),
  deposit: (id, amount) => post(`/api/accounts/accounts/${id}/deposit`, { amount }),
  transfer: (payload) => post('/api/transfer/transfers', payload),
  listTransfers: () => call('/api/transfer/transfers'),
  audit: (id) => call(`/api/audit/audit/accounts/${id}`),
  breakers: () => call('/api/transfer/actuator/circuitbreakers'),
  health: (svc) => call(`/api/${svc}/actuator/health`),
}

export const yen = (n) => `¥${Number(n).toLocaleString('en-US')}`
