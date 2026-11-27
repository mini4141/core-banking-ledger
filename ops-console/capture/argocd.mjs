// Logs in to Argo CD (admin) and screenshots the applications overview.
//   ARGO_PW=... OUT=file.png node capture/argocd.mjs https://localhost:18443
import { chromium } from '@playwright/test'

const base = process.argv[2]
const browser = await chromium.launch()
const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1440, height: 900 } })
const page = await context.newPage()
await page.goto(`${base}/login`)
await page.locator('input.argo-field').first().fill('admin')
await page.locator('input[type=password]').fill(process.env.ARGO_PW)
await page.getByRole('button', { name: 'Sign In' }).click()
await page.waitForURL('**/applications**')
await page.getByText('core-banking').first().waitFor({ timeout: 60000 })
await page.waitForTimeout(8000)
await page.screenshot({ path: process.env.OUT })
await browser.close()
console.log(`saved ${process.env.OUT}`)
