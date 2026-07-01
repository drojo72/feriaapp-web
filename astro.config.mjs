import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  output: 'static',
  site: 'https://feriaapp-web.pages.dev',
  build: {
    format: 'directory'
  },
  vite: {
    css: {
      devSourcemap: true
    }
  }
});
