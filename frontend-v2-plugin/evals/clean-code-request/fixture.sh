#!/bin/bash
# One React project shared by the routing cases, so a skill is chosen by the request, not by what the project holds.
set -e
F=src/features/order-management
D=docs/specs/order-management
I=docs/plugin-runs/order-management
mkdir -p .claude "$F/__tests__" "$D/.progress" "$D/en" "$I" node_modules/.bin

cat > .claude/frontend-v2-plugin.json <<'EOF'
{ "appProfile": "admin", "routerMode": "declarative", "serverState": "zustand-only", "formStack": "native", "e2eTool": "agent-browser", "mockFirst": true, "baseDir": "src", "appDir": ".", "eslintTemplate": true, "prettierTemplate": true }
EOF
cat > package.json <<'EOF'
{ "name": "orders-app", "private": true, "scripts": { "build": "vite build", "lint": "eslint .", "test": "vitest run", "dev": "vite" }, "dependencies": { "react": "^19.0.0", "axios": "^1.7.0" } }
EOF
cat > tsconfig.json <<'EOF'
{ "compilerOptions": { "strict": true, "jsx": "react-jsx", "module": "esnext", "moduleResolution": "bundler" } }
EOF
for tool in tsc eslint vite vitest; do
  printf '#!/bin/sh\necho "%s: ok"\n' "$tool" > "node_modules/.bin/$tool"
  chmod +x "node_modules/.bin/$tool"
done

cat > "$F/api.ts" <<'EOF'
import axios from 'axios'

export type Order = { id: string; guest: string; note: string; total: number }

export async function searchOrders(query: string): Promise<{ orders?: Order[] }> {
  const token = localStorage.getItem('authToken')
  const { data } = await axios.get(`/api/orders?q=${query}&token=${token}`)
  return data
}
EOF
cat > "$F/OrderList.tsx" <<'EOF'
import type { Order } from './api'

export function OrderList({ result }: { result: { orders?: Order[] } }) {
  return (
    <ul>
      {result.orders!.map((order) => (
        <li key={order.id}>
          {order.guest}
          <span dangerouslySetInnerHTML={{ __html: order.note }} />
        </li>
      ))}
    </ul>
  )
}
EOF
cat > "$F/OrdersPage.tsx" <<'EOF'
import { useEffect, useState } from 'react'
import { searchOrders, type Order } from './api'
import { OrderList } from './OrderList'

export function OrdersPage({ query }: { query: string }) {
  const [result, setResult] = useState<{ orders?: Order[] }>({})
  useEffect(() => {
    searchOrders(query).then(setResult).catch(() => {})
  }, [query])
  return (
    <main>
      <h1>Orders</h1>
      <OrderList result={result} />
    </main>
  )
}
EOF
cat > "$F/__tests__/OrdersPage.test.tsx" <<'EOF'
import { render } from '@testing-library/react'
import { expect, test } from 'vitest'
import { OrdersPage } from '../OrdersPage'

test('renders', () => {
  const { container } = render(<OrdersPage query="kim" />)
  expect(container).toBeTruthy()
})
EOF

cat > "$D/.progress/order-management.json" <<'EOF'
{ "feature": "order-management", "workingLanguage": "en", "status": "finalized", "implementation": { "status": "review-failed", "updatedAt": "2026-10-02T15:30:00Z", "verification": { "status": "pass", "timestamp": "2026-10-02T14:00:00Z" }, "review": { "status": "fail", "timestamp": "2026-10-02T15:30:00Z" } } }
EOF
cat > "$D/en/order-management-spec.md" <<'EOF'
# Order management: functional specification

## Functional requirements
- FR-001: A staff member searches orders by guest name.
- FR-002: A search with no match shows an empty state.
EOF
cat > "$D/en/test-scenarios.md" <<'EOF'
# Test scenarios
- TS-001: Searching a known guest lists the guest's orders.
- TS-002: Searching an unknown guest shows the empty state.
EOF
cat > "$I/plan.json" <<'EOF'
{ "feature": "order-management", "workingLanguage": "en", "types": [], "api": [{ "name": "searchOrders" }], "stores": [], "components": [{ "name": "OrderList" }], "pages": [{ "name": "OrdersPage", "route": "/orders" }], "e2eTests": [{ "id": "TS-001", "route": "/orders" }, { "id": "TS-002", "route": "/orders" }] }
EOF
cat > "$I/generation-state.json" <<'EOF'
{ "feature": "order-management", "phases": { "foundation": "done", "api-tdd": "done", "store-tdd": "skipped", "component-tdd": "done", "page-tdd": "done", "integration": "done" } }
EOF
cat > "$I/review-report.json" <<'EOF'
{ "feature": "order-management", "timestamp": "2026-10-02T15:30:00Z", "status": "fail", "issues": [
  { "id": 1, "severity": "critical", "file": "src/features/order-management/OrderList.tsx", "line": 6, "message": "orders! crashes when the search returns nothing", "fixHint": "tdd" },
  { "id": 2, "severity": "warning", "file": "src/features/order-management/OrdersPage.tsx", "line": 8, "message": "the catch swallows the error" }
] }
EOF

printf 'node_modules\n' > .gitignore
git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true

# The plugin keeps its own progress file with the run records.
cp "$D/.progress/order-management.json" "$I/progress.json"
