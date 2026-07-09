/**
 * FeriaApp API Client
 * Cliente HTTP universal para frontend
 * 
 * En producción (Cloudflare): usa /api/* (mismo dominio, no CORS)
 * En desarrollo (local): usa proxy Vite → Render
 */

const API_BASE = '/api';  // ← Ruta relativa, resuelve a Cloudflare Function

/**
 * Cliente API con auth automático
 * @param {string} endpoint - Ruta del endpoint (ej: '/auth/login')
 * @param {Object} options - Opciones de fetch
 * @returns {Promise<{ok, status, data}|null>}
 */
export async function api(endpoint, options = {}) {
  const token = localStorage.getItem('feriaapp_token');

  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    ...options.headers
  };

  const body = options.body && typeof options.body === 'object' 
    ? JSON.stringify(options.body) 
    : options.body;

  try {
    const response = await fetch(API_BASE + endpoint, {
      ...options,
      headers,
      body
    });

    const data = await response.json().catch(() => null);

    // Auto-logout en 401
    if (response.status === 401) {
      localStorage.removeItem('feriaapp_token');
      localStorage.removeItem('feriaapp_user');
      window.location.href = '/admin';
      return null;
    }

    return { ok: response.ok, status: response.status, data };

  } catch (error) {
    console.error('API Error:', error);
    return { ok: false, error: error.message };
  }
}

/**
 * Login con credenciales
 * @param {string} username 
 * @param {string} password 
 * @returns {Promise<boolean>}
 */
export async function login(username, password) {
  const result = await api('/auth/login', {
    method: 'POST',
    body: { username, password }
  });

  if (result?.ok && result.data?.access_token) {
    localStorage.setItem('feriaapp_token', result.data.access_token);
    if (result.data.user) {
      localStorage.setItem('feriaapp_user', JSON.stringify(result.data.user));
    }
    return true;
  }
  return false;
}

/**
 * Logout limpio
 */
export function logout() {
  localStorage.removeItem('feriaapp_token');
  localStorage.removeItem('feriaapp_user');
  window.location.href = '/admin';
}

/**
 * Verificar autenticación
 * @returns {Object|null} Usuario o null
 */
export function checkAuth() {
  const token = localStorage.getItem('feriaapp_token');
  const userStr = localStorage.getItem('feriaapp_user');

  if (!token) return null;

  try {
    return userStr ? JSON.parse(userStr) : { nombre: 'Usuario' };
  } catch {
    return { nombre: 'Usuario' };
  }
}
