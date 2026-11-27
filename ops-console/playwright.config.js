import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: 'e2e',
  timeout: 60000,
  reporter: [['list'], ['junit', { outputFile: process.env.JUNIT_OUT || 'test-results/junit.xml' }], ['html', { open: 'never' }]],
  use: { baseURL: process.env.BASE_URL || 'http://localhost:3000', screenshot: 'only-on-failure' },
})
