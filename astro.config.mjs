import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  output: 'static',  // ← Páginas estáticas + endpoints dinámicos
  site: 'https://feriaapp-web.pages.dev',
  build: {
    format: 'directory'
  },
  vite: {
    css: {
      devSourcemap: true
    },
    server: {
      proxy: {
        // Proxy local para desarrollo (npm run dev)
        '/api': {
          target: 'https://feriaapp-api.onrender.com',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, ''),
        }
      }
    }
  }
});
