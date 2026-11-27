// Headless screenshot helper used by scripts/capture-proof.sh
//   node capture/shot.mjs <url> <out.png> [waitMs] [--text "text to wait for"] [--full]
import { chromium } from '@playwright/test'

const [url, out, waitArg] = process.argv.slice(2)
const args = process.argv.slice(2)
const textIdx = args.indexOf('--text')
const waitFor = textIdx >= 0 ? args[textIdx + 1] : null
const full = args.includes('--full')
const waitMs = Number(waitArg) || 2000

const browser = await chromium.launch()
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, ignoreHTTPSErrors: true })
const page = await context.newPage()
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 })
if (waitFor) await page.getByText(waitFor).first().waitFor({ timeout: 60000 })
await page.waitForTimeout(waitMs)
for (const label of ['Dismiss', 'Close']) {
  const b = page.getByRole('button', { name: label, exact: true })
  for (let i = 0; i < 3 && (await b.count()) > 0; i++) await b.first().click({ timeout: 2000 }).catch(() => {})
}
await page.waitForTimeout(500)
await page.screenshot({ path: out, fullPage: full })
await browser.close()
console.log(`saved ${out}`)
