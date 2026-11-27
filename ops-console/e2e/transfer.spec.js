import { expect, test } from '@playwright/test'

test('operator opens two accounts, deposits and transfers money', async ({ page }) => {
  const suffix = Date.now().toString().slice(-6)
  const alice = `Alice-${suffix}`
  const bob = `Bob-${suffix}`

  await page.goto('/')
  for (const name of [alice, bob]) {
    await page.getByLabel('Customer name').fill(name)
    await page.getByRole('button', { name: 'Open account' }).click()
    await expect(page.getByTestId(`account-${name}`)).toBeVisible()
  }
  await page.getByLabel(`Deposit amount for ${alice}`).fill('50000')
  await page.getByTestId(`account-${alice}`).getByRole('button', { name: 'Deposit' }).click()
  await expect(page.getByTestId(`account-${alice}`).getByTestId('balance')).toHaveText('¥50,000')

  await page.screenshot({ path: process.env.SHOT_DIR ? `${process.env.SHOT_DIR}/01-console-accounts.png` : undefined })

  await page.getByRole('button', { name: 'Transfer', exact: true }).click()
  await page.getByLabel('From account').selectOption({ label: `${alice} (¥50,000)` })
  await page.getByLabel('To account').selectOption({ label: `${bob} (¥0)` })
  await page.getByLabel('Amount').fill('10000')
  await page.getByRole('button', { name: 'Send transfer' }).click()
  await expect(page.getByTestId('transfer-result')).toContainText('Transfer completed')

  await page.getByRole('button', { name: 'Send transfer' }).click()
  await expect(page.getByTestId('transfer-result')).toContainText('Replayed')

  await page.screenshot({ path: process.env.SHOT_DIR ? `${process.env.SHOT_DIR}/02-console-transfer.png` : undefined })

  await page.getByRole('button', { name: 'Accounts' }).click()
  await expect(page.getByTestId(`account-${alice}`).getByTestId('balance')).toHaveText('¥40,000')
  await expect(page.getByTestId(`account-${bob}`).getByTestId('balance')).toHaveText('¥10,000')
})
