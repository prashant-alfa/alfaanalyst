export interface BrandConfig {
  product_name: string
  company_name: string
  primary_domain: string
  docs_url: string
  terms_url: string
  privacy_url: string
  mcp_server_display_name: string
  mcp_client_key_name: string
  show_powered_by_default: boolean
}

export interface IntercomConfig {
  enabled: boolean
  app_id: string
  appId?: string
}
