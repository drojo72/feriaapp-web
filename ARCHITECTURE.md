# FeriaApp — Arquitectura de Producción

## Visión General

```
┌─────────────────────────────────────────────────────────────┐
│                    CLOUDFLARE (Edge)                         │
│  ┌─────────────────┐    ┌────────────────────────────────┐ │
│  │  Static Assets  │    │  Pages Functions (API Gateway) │ │
│  │  (Astro Build)  │    │  /api/* → Proxy a Render       │ │
│  │                 │    │  Rate limit, CORS, Logging     │ │
│  └─────────────────┘    └────────────────────────────────┘ │
│           │                              │                   │
│           └──────────────┬─────────────┘                   │
│                          │                                   │
│                   Cloudflare Cache                           │
└──────────────────────────┼─────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    RENDER.COM (Backend)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  FastAPI    │  │  PostgreSQL │  │  JWT Auth           │ │
│  │  (Python)   │  │  (Neon)     │  │  (bcrypt + jose)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Componentes

### 1. Cloudflare Pages (Frontend)
- **Astro** en modo `hybrid` (páginas estáticas + funciones dinámicas)
- **Free tier**: 500 builds/month, unlimited requests
- **Edge caching**: Assets estáticos cacheados globalmente
- **DDoS protection**: Incluido gratis

### 2. Cloudflare Pages Functions (API Gateway)
- **Ubicación**: `/functions/api/[[path]].js`
- **Funciones**:
  - Proxy seguro a Render (oculta URL real)
  - Rate limiting por IP (via Cloudflare nativo)
  - CORS controlado
  - Filtrado de headers sensibles
  - Logging de requests
  - Circuit breaker (503 con retry-after en fallos)
- **Free tier**: 100,000 requests/day

### 3. Render.com (Backend API)
- **FastAPI** + Uvicorn
- **PostgreSQL** en Neon
- **JWT** para autenticación
- **Free tier**: Se duerme tras 15 min (usar UptimeRobot)

### 4. Base de Datos (Neon PostgreSQL)
- **Free tier**: 500 MB
- **Serverless**: Escala a cero cuando no se usa
- **Branching**: Para desarrollo/testing

## Flujo de Request

```
1. Usuario → https://feriaapp.pages.dev/admin
   ↓
2. Cloudflare Edge (más cercano geográficamente)
   ↓
3. Astro serve la página HTML estática
   ↓
4. JavaScript carga → llama a /api/auth/login
   ↓
5. Cloudflare Function intercepta /api/* 
   → Forward a https://feriaapp-api.onrender.com/auth/login
   → Agrega headers de seguridad
   → Filtra headers sensibles de response
   ↓
6. Render recibe request, procesa, responde
   ↓
7. Cloudflare Function retorna response al cliente
   ↓
8. Frontend guarda token, redirige a dashboard
```

## Seguridad

| Capa | Medida |
|------|--------|
| **Edge** | Cloudflare DDoS protection, WAF rules |
| **Transporte** | HTTPS obligatorio (Cloudflare → Render) |
| **Auth** | JWT Bearer tokens, expiración 15 min |
| **Backend** | No expone URL real, headers filtrados |
| **DB** | SSL requerido, conexiones pooladas |

## Escalabilidad Futura (App Mobile)

| Escenario | Solución |
|-----------|----------|
| **App móvil** | Mismo endpoint `/api/*`, agregar versión `/api/v2/*` |
| **Rate limiting** | Cloudflare Workers KV para quotas por API key |
| **Push notifications** | Cloudflare Workers + Web Push API |
| **Offline sync** | Service Worker + IndexedDB + `/api/sync/batch` |
| **Multi-tenant** | Agregar `tenant_id` en JWT claims |
| **File uploads** | Cloudflare R2 (S3-compatible, $0.015/GB) |
| **Real-time** | Cloudflare Durable Objects + WebSockets |

## Variables de Entorno (Cloudflare)

```
RENDER_API_URL=https://feriaapp-api.onrender.com
ENVIRONMENT=production
```

Configurar en: Cloudflare Dashboard → Pages → Settings → Environment Variables
