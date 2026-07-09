// astro.config.mjs
import { defineConfig } from 'astro/config';
import cloudflare from '@astrojs/cloudflare'; // adapter para Cloudflare

export default defineConfig({
  output: 'static',        // ← Default, ya soporta dinámico
  adapter: cloudflare(),   // ← Para deploy en Cloudflare Pages
  site: 'https://feriaapp-web.pages.dev',
  build: {
    format: 'directory'
  },
  vite: {
    css: { devSourcemap: true },
    server: {
      proxy: {
        '/api': {
          target: 'https://feriaapp-api.onrender.com',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, ''),
        }
      }
    }
  }
});
