import { useCallback, useEffect, useState } from 'react'
import { api, yen } from './api.js'

const PAGES = ['Accounts', 'Transfer', 'Transfers', 'Audit', 'System']

export default function App() {
  const [page, setPage] = useState('Accounts')
  return (
    <div className="app">
      <header>
        <h1>Core Banking Ops Console</h1>
        <nav>
          {PAGES.map((p) => (
            <button key={p} className={p === page ? 'active' : ''} onClick={() => setPage(p)}>
              {p}
            </button>
          ))}
        </nav>
      </header>
      <main>
        {page === 'Accounts' && <Accounts />}
        {page === 'Transfer' && <TransferForm />}
        {page === 'Transfers' && <Transfers />}
        {page === 'Audit' && <Audit />}
        {page === 'System' && <System />}
      </main>
    </div>
  )
}

function useAccounts() {
  const [accounts, setAccounts] = useState([])
  const reload = useCallback(async () => {
    const res = await api.listAccounts()
    if (res.ok) setAccounts(res.body)
  }, [])
  useEffect(() => {
    reload()
  }, [reload])
  return [accounts, reload]
}

function Accounts() {
  const [accounts, reload] = useAccounts()
  const [name, setName] = useState('')
  const [amounts, setAmounts] = useState({})

  const create = async (e) => {
    e.preventDefault()
    await api.createAccount(name, 'JPY')
    setName('')
    reload()
  }
  const deposit = async (id) => {
    await api.deposit(id, amounts[id])
    setAmounts({ ...amounts, [id]: '' })
    reload()
  }

  return (
    <section>
      <h2>Accounts</h2>
      <form onSubmit={create} className="row">
        <input aria-label="Customer name" placeholder="Customer name" value={name} onChange={(e) => setName(e.target.value)} required />
        <button type="submit">Open account</button>
      </form>
      <table>
        <thead>
          <tr><th>Customer</th><th>Account ID</th><th>Balance</th><th>Deposit</th></tr>
        </thead>
        <tbody>
          {accounts.map((a) => (
            <tr key={a.id} data-testid={`account-${a.customerName}`}>
              <td>{a.customerName}</td>
              <td className="mono">{a.id}</td>
              <td className="num" data-testid="balance">{yen(a.balance)}</td>
              <td>
                <input aria-label={`Deposit amount for ${a.customerName}`} type="number" min="1" value={amounts[a.id] || ''}
                  onChange={(e) => setAmounts({ ...amounts, [a.id]: e.target.value })} />
                <button onClick={() => deposit(a.id)} disabled={!amounts[a.id]}>Deposit</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

function TransferForm() {
  const [accounts] = useAccounts()
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [amount, setAmount] = useState('10000')
  const [key, setKey] = useState(() => crypto.randomUUID())
  const [result, setResult] = useState(null)

  const submit = async (e) => {
    e.preventDefault()
    const res = await api.transfer({ idempotencyKey: key, fromAccountId: from, toAccountId: to, amount })
    setResult(res)
  }
  const options = accounts.map((a) => <option key={a.id} value={a.id}>{a.customerName} ({yen(a.balance)})</option>)

  return (
    <section>
      <h2>New transfer</h2>
      <form onSubmit={submit} className="stack">
        <label>From
          <select aria-label="From account" value={from} onChange={(e) => setFrom(e.target.value)} required>
            <option value="">select...</option>{options}
          </select>
        </label>
        <label>To
          <select aria-label="To account" value={to} onChange={(e) => setTo(e.target.value)} required>
            <option value="">select...</option>{options}
          </select>
        </label>
        <label>Amount (JPY)
          <input aria-label="Amount" type="number" min="1" value={amount} onChange={(e) => setAmount(e.target.value)} required />
        </label>
        <label>Idempotency key
          <input aria-label="Idempotency key" className="mono" value={key} onChange={(e) => setKey(e.target.value)} />
        </label>
        <div className="row">
          <button type="submit">Send transfer</button>
          <button type="button" onClick={() => setKey(crypto.randomUUID())}>New key</button>
        </div>
      </form>
      {result && (
        <div className={result.ok ? 'result ok' : 'result err'} data-testid="transfer-result">
          <strong>{result.ok ? (result.replayed ? 'Replayed (no money moved again)' : 'Transfer completed') : `Failed: ${result.body?.code || result.status}`}</strong>
          <pre>{JSON.stringify(result.body, null, 2)}</pre>
        </div>
      )}
    </section>
  )
}

function Transfers() {
  const [rows, setRows] = useState([])
  useEffect(() => {
    api.listTransfers().then((res) => res.ok && setRows(res.body))
  }, [])
  return (
    <section>
      <h2>Transfers</h2>
      <table>
        <thead><tr><th>Time</th><th>From</th><th>To</th><th>Amount</th><th>Status</th></tr></thead>
        <tbody>
          {rows.map((t) => (
            <tr key={t.id}>
              <td>{new Date(t.createdAt).toLocaleString()}</td>
              <td className="mono">{t.fromAccountId.slice(0, 8)}</td>
              <td className="mono">{t.toAccountId.slice(0, 8)}</td>
              <td className="num">{yen(t.amount)}</td>
              <td>{t.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

function Audit() {
  const [accounts] = useAccounts()
  const [id, setId] = useState('')
  const [items, setItems] = useState([])
  useEffect(() => {
    if (id) api.audit(id).then((res) => setItems(res.ok ? res.body : []))
  }, [id])
  return (
    <section>
      <h2>Audit trail (DynamoDB)</h2>
      <select aria-label="Audit account" value={id} onChange={(e) => setId(e.target.value)}>
        <option value="">select account...</option>
        {accounts.map((a) => <option key={a.id} value={a.id}>{a.customerName}</option>)}
      </select>
      <table>
        <thead><tr><th>SK</th><th>Type</th><th>Amount</th><th>Counterparty</th></tr></thead>
        <tbody>
          {items.map((i) => (
            <tr key={i.sk}>
              <td className="mono">{i.sk}</td><td>{i.type}</td><td className="num">{yen(i.amount)}</td>
              <td className="mono">{i.counterparty.slice(0, 8)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

function System() {
  const [breakers, setBreakers] = useState({})
  const [health, setHealth] = useState({})
  useEffect(() => {
    const poll = async () => {
      const b = await api.breakers().catch(() => null)
      setBreakers(b?.ok ? b.body.circuitBreakers : {})
      const next = {}
      for (const svc of ['accounts', 'transfer', 'audit']) {
        const h = await api.health(svc).catch(() => null)
        next[svc] = h?.body?.status || 'DOWN'
      }
      setHealth(next)
    }
    poll()
    const t = setInterval(poll, 2000)
    return () => clearInterval(t)
  }, [])
  return (
    <section>
      <h2>System</h2>
      <h3>Circuit breakers (transfer-service to accounts-service)</h3>
      {Object.keys(breakers).length === 0 && <p>No data (transfer-service unreachable)</p>}
      <div className="cards">
        {Object.entries(breakers).map(([name, b]) => (
          <div key={name} className={`card state-${b.state}`} data-testid={`breaker-${name}`}>
            <h4>{name}</h4>
            <div className="state">{b.state}</div>
            <small>failure rate {b.failureRate} | not permitted {b.notPermittedCalls}</small>
          </div>
        ))}
      </div>
      <h3>Service health</h3>
      <div className="cards">
        {Object.entries(health).map(([svc, status]) => (
          <div key={svc} className={`card health-${status}`}><h4>{svc}-service</h4><div className="state">{status}</div></div>
        ))}
      </div>
    </section>
  )
}
