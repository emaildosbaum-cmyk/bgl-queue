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

function checkAndSendToken() {
  try {
    const token = getSiteToken();
    if (token) {
      chrome.runtime.sendMessage({ type: 'siteTokenAvailable', token: token }).catch(() => {});
      return true;
    }
  } catch(e) {}
  return false;
}

// Sincronizacao proativa imediata e com retentativas (para suportar carregamento assincrono do token)
checkAndSendToken();
[400, 1000, 2500, 5000, 10000].forEach(ms => setTimeout(checkAndSendToken, ms));

// Observa alteracao dinamica no input do token na pagina
try {
  const tokenInput = document.getElementById('scriptTokenDisplay');
  if (tokenInput) {
    tokenInput.addEventListener('input', () => checkAndSendToken());
    tokenInput.addEventListener('change', () => checkAndSendToken());
  }
} catch(e) {}
