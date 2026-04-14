<template>
  <div class="bg-gray-50">
    <UNotifications />
    <slot />
  </div>
</template>

<script setup lang="ts">
const { signIn, signOut, token, data: currentUser, status, lastRefreshedAt, getSession } = useAuth()
const { $intercom } = useNuxtApp()
const { environment, intercom } = useRuntimeConfig().public
const route = useRoute()
const intercomConfig = (intercom as any) || {}
const intercomEnabled = environment === 'production' && intercomConfig.enabled === true
const intercomRawAppId = intercomConfig.app_id ?? intercomConfig.appId
const intercomAppId = typeof intercomRawAppId === 'string' ? intercomRawAppId.trim() : ''

if (intercomEnabled && intercomAppId) {
  $intercom.boot({ app_id: intercomAppId })
} else if (intercomEnabled && !intercomAppId) {
  console.warn('Intercom enabled but app ID is missing. Skipping Intercom boot.')
}

onMounted(async () => {
  // If redirected with an access_token in query, let the target page set the token first
  if (route.query.access_token) {
    return
  }
  await getSession({ force: true })
})

</script>
