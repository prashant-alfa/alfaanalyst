import { computed } from 'vue'

export function useBranding() {
  const runtime = useRuntimeConfig()
  const brand = computed(() => (runtime.public as any).brand || {})

  const productName = computed(() => brand.value.product_name || 'Alfa Analyst')
  const companyName = computed(() => brand.value.company_name || 'Alfastack')
  const primaryDomain = computed(() => brand.value.primary_domain || 'https://analyst.alfastack.cloud')
  const docsUrl = computed(() => brand.value.docs_url || `${primaryDomain.value}/docs`)
  const termsUrl = computed(() => brand.value.terms_url || `${primaryDomain.value}/terms`)
  const privacyUrl = computed(() => brand.value.privacy_url || `${primaryDomain.value}/privacy`)
  const mcpServerDisplayName = computed(() => brand.value.mcp_server_display_name || `${productName.value} MCP Server`)
  const mcpClientKeyName = computed(() => brand.value.mcp_client_key_name || 'alfastack')
  const showPoweredByDefault = computed(() => Boolean(brand.value.show_powered_by_default))

  return {
    brand,
    productName,
    companyName,
    primaryDomain,
    docsUrl,
    termsUrl,
    privacyUrl,
    mcpServerDisplayName,
    mcpClientKeyName,
    showPoweredByDefault,
  }
}
