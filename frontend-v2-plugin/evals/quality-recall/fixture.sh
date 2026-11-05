#!/bin/bash
set -e
mkdir -p .claude
cat > package.json <<'EOF'
{ "name": "orders-app", "private": true, "dependencies": { "react": "^19.0.0", "react-i18next": "^15.0.0", "axios": "^1.7.0" } }
EOF
cat > tsconfig.json <<'EOF'
{ "compilerOptions": { "strict": true, "jsx": "react-jsx", "module": "esnext", "moduleResolution": "bundler" } }
EOF
cat > .claude/frontend-v2-plugin.json <<'EOF'
{ "appProfile": "admin", "routerMode": "declarative", "serverState": "zustand-only", "formStack": "native", "baseDir": "src", "appDir": "." }
EOF
mkdir -p "$(dirname src/features/orders/api.ts)"
cat > src/features/orders/api.ts <<'EOF'
import axios from 'axios'
import { MOCK_ORDERS } from './mocks'

export interface Order {
  id: string
  total: number
  status: 'open' | 'paid'
  createdAt: string
}

export async function searchOrders(query: string): Promise<Order[]> {
  if (process.env.NODE_ENV === 'test') return MOCK_ORDERS
  const res = await axios.get('/api/orders', { params: { query } })
  return res.data as any
}

export async function cancelOrder(id: string): Promise<boolean> {
  try {
    await axios.post(`/api/orders/${id}/cancel`)
    return true
  } catch (e) {}
  return false
}
EOF
mkdir -p "$(dirname src/features/orders/mocks.ts)"
cat > src/features/orders/mocks.ts <<'EOF'
import type { Order } from './api'

export const MOCK_ORDERS: Order[] = [
  { id: 'ORD-1', total: 1200, status: 'open', createdAt: '2026-01-02T00:00:00Z' },
]
EOF
mkdir -p "$(dirname src/features/orders/hooks/useOrderSearch.ts)"
cat > src/features/orders/hooks/useOrderSearch.ts <<'EOF'
import { useEffect, useState } from 'react'
import { searchOrders, type Order } from '../api'

export function useOrderSearch(query: string) {
  const [results, setResults] = useState<Order[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    searchOrders(query)
      .then((rows) => {
        setResults(rows)
        setLoading(false)
      })
      .catch((e: Error) => setError(e.message))
  }, [query])

  return { results, loading, error }
}
EOF
mkdir -p "$(dirname src/features/orders/hooks/useOnlineStatus.ts)"
cat > src/features/orders/hooks/useOnlineStatus.ts <<'EOF'
import { useEffect, useState } from 'react'

export function useOnlineStatus(): boolean {
  const [online, setOnline] = useState(navigator.onLine)

  useEffect(() => {
    window.addEventListener('online', () => setOnline(true))
    window.addEventListener('offline', () => setOnline(false))
  }, [])

  return online
}
EOF
mkdir -p "$(dirname src/features/orders/hooks/useAutoRefresh.ts)"
cat > src/features/orders/hooks/useAutoRefresh.ts <<'EOF'
import { useEffect, useState } from 'react'

export function useAutoRefresh(onTick: () => void, seconds: number): number {
  const [ticks, setTicks] = useState(0)

  useEffect(() => {
    const id = setInterval(() => {
      setTicks(ticks + 1)
      onTick()
    }, seconds * 1000)
    return () => clearInterval(id)
  }, [])

  return ticks
}
EOF
mkdir -p "$(dirname src/features/orders/hooks/useDebouncedValue.ts)"
cat > src/features/orders/hooks/useDebouncedValue.ts <<'EOF'
import { useEffect, useState } from 'react'

export function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value)

  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs)
    return () => clearTimeout(id)
  }, [value, delayMs])

  return debounced
}
EOF
mkdir -p "$(dirname src/features/orders/format/formatterFactory.ts)"
cat > src/features/orders/format/formatterFactory.ts <<'EOF'
export interface PriceFormatter {
  price(value: number): string
}

class DefaultPriceFormatter implements PriceFormatter {
  price(value: number): string {
    return new Intl.NumberFormat('ko-KR').format(value)
  }
}

export function getFormatter(): PriceFormatter {
  return new DefaultPriceFormatter()
}
EOF
mkdir -p "$(dirname src/features/orders/utils/totals.ts)"
cat > src/features/orders/utils/totals.ts <<'EOF'
import type { Order } from '../api'

/** Returns the sum of the order totals, in cents. */
export function get_order_total(orders: Order[]): number {
  return orders.reduce((sum, order) => sum + order.total, 0)
}
EOF
mkdir -p "$(dirname src/features/orders/utils/match.ts)"
cat > src/features/orders/utils/match.ts <<'EOF'
const ORDER_ID = /^ORD-\d+$/g

export function isOrderId(value: string): boolean {
  return ORDER_ID.test(value)
}
EOF
mkdir -p "$(dirname src/features/orders/utils/preferences.ts)"
cat > src/features/orders/utils/preferences.ts <<'EOF'
export interface Prefs {
  pageSize: number
  sort: 'asc' | 'desc'
}

const DEFAULTS: Prefs = { pageSize: 20, sort: 'desc' }

export function withDefaults(overrides: Partial<Prefs>): Prefs {
  return Object.assign(DEFAULTS, overrides)
}

export function loadPrefs(): Prefs {
  return withDefaults(JSON.parse(localStorage.getItem('order-prefs')!))
}
EOF
mkdir -p "$(dirname src/features/orders/utils/dates.ts)"
cat > src/features/orders/utils/dates.ts <<'EOF'
export function formatOrderDate(iso: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(iso))
}
EOF
mkdir -p "$(dirname src/features/orders/components/CancelButton.tsx)"
cat > src/features/orders/components/CancelButton.tsx <<'EOF'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { cancelOrder } from '../api'

interface CancelButtonProps {
  id: string
  onDone: () => void
}

export function CancelButton({ id, onDone }: CancelButtonProps) {
  const { t } = useTranslation('orders')
  const [busy, setBusy] = useState(false)

  const click = async () => {
    setBusy(true)
    await cancelOrder(id)
    onDone()
    setBusy(false)
  }

  return <button onClick={click}>{busy ? t('cancelling') : t('cancel')}</button>
}
EOF
mkdir -p "$(dirname src/features/orders/components/OrderFilters.tsx)"
cat > src/features/orders/components/OrderFilters.tsx <<'EOF'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'

interface OrderFiltersProps {
  initialQuery: string
  statuses: string[]
  onSearch: (query: string) => void
}

export function OrderFilters({ initialQuery, statuses, onSearch }: OrderFiltersProps) {
  const { t } = useTranslation('orders')
  const [query, setQuery] = useState(initialQuery)
  const [options] = useState(statuses)

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        onSearch(query)
      }}
    >
      <input value={query} onChange={(e) => setQuery(e.target.value)} aria-label={t('search')} />
      <select aria-label={t('status')}>
        {options.map((status) => (
          <option key={status}>{status}</option>
        ))}
      </select>
    </form>
  )
}
EOF
mkdir -p "$(dirname src/features/orders/components/OrderTable.tsx)"
cat > src/features/orders/components/OrderTable.tsx <<'EOF'
import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import type { Order } from '../api'
import { formatOrderDate } from '../utils/dates'
import { CancelButton } from './CancelButton'

interface OrderTableProps {
  orders: Order[]
  locale: string
  onChanged: () => void
}

export function OrderTable({ orders, locale, onChanged }: OrderTableProps) {
  const { t } = useTranslation('orders')
  const sorted = orders.sort((a, b) => b.total - a.total)
  const money = useMemo(() => new Intl.NumberFormat(locale), [])

  return (
    <table>
      <caption>
        {t('orders')} {orders.length && <span>{orders.length}</span>}
      </caption>
      <tbody>
        {sorted.map((order) => (
          <tr key={order.id}>
            <td>{order.id}</td>
            <td>{money.format(order.total)}</td>
            <td>{formatOrderDate(order.createdAt, locale)}</td>
            <td>
              <CancelButton id={order.id} onDone={onChanged} />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}
EOF
mkdir -p "$(dirname src/features/orders/components/EmptyState.tsx)"
cat > src/features/orders/components/EmptyState.tsx <<'EOF'
import { useTranslation } from 'react-i18next'

export function EmptyState() {
  const { t } = useTranslation('orders')
  return <p role="status">{t('empty')}</p>
}
EOF
mkdir -p "$(dirname src/features/orders/components/OrderSummary.tsx)"
cat > src/features/orders/components/OrderSummary.tsx <<'EOF'
import type { Order } from '../api'
import { getFormatter } from '../format/formatterFactory'

export function OrderSummary({ orders }: { orders: Order[] }) {
  const total = orders.reduce((sum, order) => sum + order.total, 0)
  return <strong>{getFormatter().price(total)}</strong>
}
EOF
mkdir -p "$(dirname src/features/orders/pages/OrdersPage.tsx)"
cat > src/features/orders/pages/OrdersPage.tsx <<'EOF'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { EmptyState } from '../components/EmptyState'
import { OrderFilters } from '../components/OrderFilters'
import { OrderSummary } from '../components/OrderSummary'
import { OrderTable } from '../components/OrderTable'
import { useAutoRefresh } from '../hooks/useAutoRefresh'
import { useDebouncedValue } from '../hooks/useDebouncedValue'
import { useOnlineStatus } from '../hooks/useOnlineStatus'
import { useOrderSearch } from '../hooks/useOrderSearch'

export function OrdersPage({ legacyMode }: { legacyMode?: boolean }) {
  const { t, i18n } = useTranslation('orders')
  const [query, setQuery] = useState('')
  const debounced = useDebouncedValue(query, 200)
  const { results, loading, error } = useOrderSearch(debounced)
  const online = useOnlineStatus()
  useAutoRefresh(() => setQuery((value) => value), 30)

  if (error) return <p role="alert">{error}</p>
  if (loading) return <p role="status">{t('loading')}</p>

  return (
    <section>
      <h1>Orders</h1>
      {!online && <p role="status">{t('offline')}</p>}
      <OrderFilters initialQuery={query} statuses={['open', 'paid']} onSearch={setQuery} />
      {results.length === 0 ? (
        <EmptyState />
      ) : (
        <OrderTable orders={results} locale={i18n.language} onChanged={() => setQuery((value) => value)} />
      )}
      <OrderSummary orders={results} />
    </section>
  )
}
EOF
