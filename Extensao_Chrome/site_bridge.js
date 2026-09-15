// site_bridge.js — Content Script injetado em https://bgl-queue.vercel.app/*
// Permite que a extensao se conecte automaticamente e sincronize o token com 1 clique

function getSiteToken() {
  const input = document.getElementById('scriptTokenDisplay');
  if (input && input.value && input.value !== 'bgl_default_master') {
    return input.value.trim();
  }
  const fromStorage = localStorage.getItem('bgl_token');
  if (fromStorage) return fromStorage.trim();
  
  const discordUser = localStorage.getItem('bgl_discord_user');
  if (discordUser) {
    try {
      const u = JSON.parse(discordUser);
      if (u && (u.token || u.uid)) return (u.token || u.uid);
    } catch(e) {}
  }
  return null;
}

// Responde a mensagens diretas da extensao (popup ou background)
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === 'getSiteToken') {
    const token = getSiteToken();
    sendResponse({ ok: true, token: token });
    return true;
  }
});

// Sincronizacao proativa: se a pagina acabou de carregar com usuario logado
try {
  const token = getSiteToken();
  if (token) {
    chrome.runtime.sendMessage({ type: 'siteTokenAvailable', token: token }).catch(() => {});
  }
} catch(e) {}
