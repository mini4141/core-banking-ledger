// Opens the console System page and screenshots it once a circuit breaker shows OPEN (or HALF_OPEN).
//   node capture/breaker.mjs <url> <out.png>
import { chromium } from '@playwright/test'

const [url, out] = process.argv.slice(2)
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } })
await page.goto(url)
await page.getByRole('button', { name: 'System', exact: true }).click()
await page.getByTestId('breaker-accounts').getByText(/^OPEN$/).waitFor({ timeout: 90000 })
await page.waitForTimeout(500)
await page.screenshot({ path: out })
await browser.close()
console.log(`saved ${out}`)
