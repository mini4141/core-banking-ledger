// Logs in to Grafana (admin/admin) and screenshots the Core Banking dashboard.
//   node capture/grafana.mjs http://localhost:13001 out.png
import { chromium } from '@playwright/test'

const [base, out] = process.argv.slice(2)
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } })
await page.goto(`${base}/login`)
await page.locator('input[name=user]').fill('admin')
await page.locator('input[name=password]').fill('admin')
await page.getByRole('button', { name: /log in/i }).click()
await page.waitForTimeout(3000)
await page.goto(`${base}/d/core-banking/core-banking-ledger?orgId=1&from=now-15m&to=now&kiosk`)
await page.waitForTimeout(12000)
await page.screenshot({ path: out })
await browser.close()
console.log(`saved ${out}`)
