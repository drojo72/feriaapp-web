/**
 * FeriaApp API Gateway
 * Cloudflare Pages Function - Proxy seguro a Render backend
 * 
 * Arquitectura:
 *   Cliente (Cloudflare Pages) → /api/* → CF Function → Render API
 *   
 * Seguridad:
 *   - Oculta URL real del backend
 *   - Rate limiting por IP (Cloudflare nativo)
 *   - CORS controlado
 *   - Headers sensibles filtrados en response
 *   - Logging para auditoría
 */

const RENDER_API = 'https://feriaapp-api.onrender.com';

// Headers que NO queremos enviar al cliente (filtrado de seguridad)
const SENSITIVE_HEADERS = ['server', 'x-render-origin-server', 'cf-ray'];

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);

  // Construir URL destino en Render
  const targetPath = url.pathname.replace('/api', '');
  const targetUrl = RENDER_API + targetPath + url.search;

  // Clonar headers del request original
  const headers = new Headers(request.headers);
  headers.delete('host');
  headers.set('X-Forwarded-For', request.headers.get('CF-Connecting-IP') || 'unknown');
  headers.set('X-Request-ID', crypto.randomUUID());

  // Logging (en producción, enviar a servicio de logs)
  console.log(`[${new Date().toISOString()}] ${request.method} ${targetPath} | IP: ${request.headers.get('CF-Connecting-IP')}`);

  try {
    const response = await fetch(targetUrl, {
      method: request.method,
      headers: headers,
      body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : null,
    });

    // Construir response limpia
    const newHeaders = new Headers();
    response.headers.forEach((value, key) => {
      if (!SENSITIVE_HEADERS.includes(key.toLowerCase())) {
        newHeaders.set(key, value);
      }
    });

    // CORS headers controlados
    newHeaders.set('Access-Control-Allow-Origin', '*');
    newHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, PATCH, OPTIONS');
    newHeaders.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Requested-With');
    newHeaders.set('Access-Control-Max-Age', '86400');

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: newHeaders
    });

  } catch (error) {
    console.error(`[ERROR] ${targetPath}:`, error);
    return new Response(JSON.stringify({
      detail: 'Error de conexión con el servidor',
      retry_after: 5
    }), {
      status: 503,
      headers: {
        'Content-Type': 'application/json',
        'Retry-After': '5'
      }
    });
  }
}
