import { defineNuxtConfig } from "nuxt/config"

const intercomModuleAppId = process.env.NUXT_PUBLIC_INTERCOM_APP_ID || process.env.BOW_INTERCOM_APP_ID || 'disabled'

export default defineNuxtConfig({
  devtools: { enabled: true },
  ssr: false,

  modules: [
    "@nuxt/ui",
    "@sidebase/nuxt-auth",
    'nuxt-tiptap-editor',
    '@nuxtjs/mdc',
    '@nuxt-alt/proxy',
    'nuxt-3-intercom',
    'nuxt-echarts',
    'nuxt-monaco-editor'
  ],

  echarts: {
    charts: [
      'BarChart',
      'LineChart',
      'PieChart',
      'ScatterChart',
      'EffectScatterChart',
      'BoxplotChart',
      'CandlestickChart',
      'GaugeChart',
      'FunnelChart',
      'HeatmapChart',
      'LinesChart',
      'MapChart',
      'ParallelChart',
      'RadarChart',
      'SunburstChart',
      'TreeChart',
      'TreemapChart'
    ],
    components: [
      'AriaComponent',
      'AxisPointerComponent',
      'BrushComponent',
      'CalendarComponent',
      'DataZoomComponent',
      'DataZoomInsideComponent',
      'DataZoomSliderComponent',
      'DatasetComponent',
      'GridComponent',
      'LegendComponent',
      'MarkLineComponent',
      'MarkPointComponent',
      'ParallelComponent',
      'RadarComponent'
    ]
  },

  intercom: {
    appId: intercomModuleAppId,
    autoBoot: false
  },

  tiptap: {
    prefix: 'Tiptap'
  },

  app: {
    head: {
      title: process.env.NUXT_PUBLIC_PRODUCT_NAME || 'Alfa Analyst',
      meta: [
        { name: 'description', content: 'AI Powered Data Analyst' }
      ]
    }
  },

  plugins: [
    '~/plugins/vue-draggable-resizable.client.js',
    '~/plugins/vue-flow.client.js',
  ],

  icon: {
    localApiEndpoint: '/_nuxt_icon'
  },

  colorMode: {
    preference: 'light'
  },

  proxy: {
    debug: true,
    experimental: {
      listener: true
    },
    proxies: {
      '/ws/api': {
        target: `ws://127.0.0.1:${process.env.BACKEND_PORT || 8000}`,
        ws: true,
        changeOrigin: true,
        secure: false,
        rewrite: (path) => path,
        headers: {
          'Upgrade': 'websocket',
          'Connection': 'Upgrade'
        }
      },
      '/mcp': {
        target: `http://127.0.0.1:${process.env.BACKEND_PORT || 8000}`,
        changeOrigin: true,
        secure: false,
        rewrite: (path) => `/api${path}`
      },
      '/api': {
        target: `http://127.0.0.1:${process.env.BACKEND_PORT || 8000}`,
        changeOrigin: true,
        secure: false,
        rewrite: (path) => path
      }
    }
  },

  auth: {
    baseURL: '/api/', // Proxy now handled by NGINX
    provider: {
      type: 'local',
      pages: {
        login: '/users/sign-in',
        signup: '/users/sign-up'
      },
      endpoints: {
        signIn: { path: '/auth/jwt/login', method: 'post' },
        signOut: { path: '/auth/jwt/logout', method: 'post' },
        signUp: { path: '/auth/jwt/register', method: 'post' },
        getSession: { path: '/users/whoami', method: 'get' }
      },
      token: {
        signInResponseTokenPointer: '/access_token',
        type: 'Bearer',
        maxAgeInSeconds: 60 * 60 * 24 * 7, // 7 days
        cookie: {
          name: 'auth_token',
          options: {
            path: '/',
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'lax'
          }
        }
      },
      sessionDataType: {
        id: 'integer', name: 'string', email: 'string', is_superuser: 'boolean',
        organizations: '{ name: string, description: string | null, id: string, role: string }[]'
      },
    },
    session: {
      enableRefreshOnWindowFocus: true,
      enableRefreshPeriodically: false
    },
    globalAppMiddleware: {
      isEnabled: true
    },
    rewriteRedirects: true,
    fullPathRedirect: true
  },

  runtimeConfig: {
    public: {
      baseURL: '/api',
      wsURL: '/ws/api',
      environment: process.env.NODE_ENV,
      intercom: {
        enabled: process.env.NUXT_PUBLIC_INTERCOM_ENABLED === 'true',
        app_id: process.env.NUXT_PUBLIC_INTERCOM_APP_ID || process.env.BOW_INTERCOM_APP_ID || '',
      },
      brand: {
        product_name: process.env.NUXT_PUBLIC_PRODUCT_NAME || 'Alfa Analyst',
        company_name: process.env.NUXT_PUBLIC_COMPANY_NAME || 'Alfastack',
        primary_domain: process.env.NUXT_PUBLIC_PRIMARY_DOMAIN || 'https://analyst.alfastack.cloud',
        docs_url: process.env.NUXT_PUBLIC_DOCS_URL || 'https://analyst.alfastack.cloud/docs',
        terms_url: process.env.NUXT_PUBLIC_TERMS_URL || 'https://analyst.alfastack.cloud/terms',
        privacy_url: process.env.NUXT_PUBLIC_PRIVACY_URL || 'https://analyst.alfastack.cloud/privacy',
        mcp_server_display_name: process.env.NUXT_PUBLIC_MCP_SERVER_DISPLAY_NAME || 'Alfa Analyst MCP Server',
        mcp_client_key_name: process.env.NUXT_PUBLIC_MCP_CLIENT_KEY_NAME || 'alfastack',
        show_powered_by_default: process.env.NUXT_PUBLIC_SHOW_POWERED_BY_DEFAULT === 'true',
      }
    }
  },

  nitro: {
    experimental: {
      websocket: false
    }
  },

  // Allow ngrok domains to access the dev server (for Slack webhooks via frontend proxy)
  vite: {
    server: {
      allowedHosts: [
        '.ngrok-free.app'
      ]
    }
  },

  compatibilityDate: '2025-08-03',
})
