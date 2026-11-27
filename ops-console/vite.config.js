import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const target = (port) => ({ target: `http://localhost:${port}`, changeOrigin: true, rewrite: (p) => p.replace(/^\/api\/[a-z]+/, '') })

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api/accounts': target(8081),
      '/api/transfer': target(8082),
      '/api/audit': target(8083),
    },
  },
})
