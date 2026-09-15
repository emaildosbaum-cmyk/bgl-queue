(function () {
  'use strict';

  let VALID_KEYS = ['TSK_MODDED', 'JOAOLEGAL', 'BGL', 'ADMIN'];

  const statusEl = document.getElementById('status');
  const keyInput = document.getElementById('keyInput');
  const activateBtn = document.getElementById('activateBtn');
  const refreshHint = document.getElementById('refreshHint');
  const toast = document.getElementById('toast');
  const toastIcon = document.getElementById('toastIcon');
  const toastLabel = document.getElementById('toastLabel');
  const toastSub = document.getElementById('toastSub');

  let toastTimer = null;
  let statsInterval = null;

  function showToast(icon, label, sub, success) {
    toastIcon.textContent = icon;
    toastLabel.textContent = label;
    toastLabel.style.color = success ? '#ffffff' : 'rgba(255,255,255,0.6)';
    toastSub.textContent = sub;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 1800);
  }

  function showValid(key, announce) {
    statusEl.className = 'status ok';
    statusEl.textContent = '[OK] Ativado - ' + key;
    keyInput.style.display = 'none';
    refreshHint.classList.add('show');

    activateBtn.textContent = 'Desativar';
    activateBtn.disabled = false;
    activateBtn.style.background = 'linear-gradient(135deg,#1a1a1a,#0a0a0a)';
    activateBtn.style.borderColor = 'rgba(255,255,255,0.08)';
    activateBtn.style.color = 'rgba(255,255,255,0.45)';
    activateBtn.onclick = deactivate;

    if (announce) {
      showToast('[OK]', 'Ativado com sucesso!', key, true);
    }

    showDashboard();
  }

  function showInvalid() {
    statusEl.className = 'status bad';
    statusEl.textContent = 'Nenhuma chave ativada';
    keyInput.style.display = '';

    activateBtn.textContent = 'Ativar';
    activateBtn.disabled = false;
    activateBtn.style.background = 'linear-gradient(135deg, #2a2a2a 0%, #111 100%)';
    activateBtn.style.borderColor = 'rgba(255,255,255,0.15)';
    activateBtn.style.color = '#fff';
    activateBtn.onclick = activate;

    showLicense();
  }

  function activate() {
    const key = keyInput.value.trim().toUpperCase();

    if (key.length < 3) {
      showToast('[X]', 'Chave muito curta', 'digite a senha joaolegal', false);
      return;
    }

    if (VALID_KEYS.indexOf(key) !== -1 || key === 'JOAOLEGAL') {
      chrome.storage.local.set({ licenseValid: true, licenseKey: key }, () => showValid(key, true));
    } else {
      showToast('[X]', 'Chave inválida', 'use a senha joaolegal', false);
    }
  }

  function deactivate() {
    chrome.storage.local.set({ licenseValid: false, licenseKey: null }, () => location.reload());
  }

  function startSimulatedStats() {
    if (statsInterval) clearInterval(statsInterval);

    const dashboard = document.getElementById('dashboard');
    const licenseScreen = document.getElementById('licenseScreen');
    const pageElem = document.getElementById('pageAds');
    const totalElem = document.getElementById('totalAds');
    const trackersElem = document.getElementById('trackers');
    const bandwidthElem = document.getElementById('bandwidth');
    const timeElem = document.getElementById('timeSaved');

    let pageAds = 0;
    let totalAds = 0;
    let trackers = 0;
    let bandwidth = 0;
    let timeSaved = 0;

    function updateStats() {
      if (pageElem) pageElem.innerText = pageAds;
      if (totalElem) totalElem.innerText = totalAds.toLocaleString();
      if (trackersElem) trackersElem.innerText = trackers;
      if (bandwidthElem) bandwidthElem.innerText = bandwidth.toFixed(1) + ' MB';
      if (timeElem) timeElem.innerText = timeSaved.toFixed(1) + 's';

      if (pageElem) pageElem.classList.add('bump');
      setTimeout(() => { if (pageElem) pageElem.classList.remove('bump'); }, 350);
    }

    statsInterval = setInterval(() => {
      if (!dashboard || dashboard.style.display !== 'block') return;
      pageAds += Math.floor(Math.random() * 3) + 1;
      totalAds += Math.floor(Math.random() * 5) + 2;
      trackers += Math.random() > 0.6 ? Math.floor(Math.random() * 2) + 1 : 0;
      bandwidth += 0.05;
      timeSaved += 0.03;
      updateStats();
    }, 2000);
  }

  function showDashboard() {
    const licenseScreen = document.getElementById('licenseScreen');
    const dashboard = document.getElementById('dashboard');
    if (licenseScreen) licenseScreen.style.display = 'none';
    if (dashboard) dashboard.style.display = 'block';
    document.body.classList.add('protected');
    startSimulatedStats();
  }

  function showLicense() {
    const licenseScreen = document.getElementById('licenseScreen');
    const dashboard = document.getElementById('dashboard');
    if (licenseScreen) licenseScreen.style.display = 'block';
    if (dashboard) dashboard.style.display = 'none';
    document.body.classList.remove('protected');
  }

  function init(data) {
    if (data.licenseValid && data.licenseKey) {
      if (VALID_KEYS.indexOf(data.licenseKey.toUpperCase()) !== -1) {
        showValid(data.licenseKey, false);
        showDashboard();
      } else {
        chrome.storage.local.set({ licenseValid: false, licenseKey: null });
        showInvalid();
        showLicense();
      }
    } else {
      showInvalid();
      showLicense();
    }
  }

  chrome.storage.local.get(['licenseValid', 'licenseKey'], init);
  // ═════════════════════════════════════════════════════════════
  // MULTI-TENANT PLAYER ID CONFIGURATION
  // ═════════════════════════════════════════════════════════════
  const tenantInputLic = document.getElementById('tenantInputLic');
  const tenantSaveBtnLic = document.getElementById('tenantSaveBtnLic');
  const tenantStatusTextLic = document.getElementById('tenantStatusTextLic');
  const tenantDotLic = document.getElementById('tenantDotLic');

  const tenantInputDash = document.getElementById('tenantInputDash');
  const tenantSaveBtnDash = document.getElementById('tenantSaveBtnDash');
  const tenantStatusTextDash = document.getElementById('tenantStatusTextDash');
  const tenantDotDash = document.getElementById('tenantDotDash');
  const tenantClearBtn = document.getElementById('tenantClearBtn');

  function parseUserId(raw) {
    if (!raw) return null;
    let s = String(raw).trim();
    if (!s) return null;
    if (s.includes('token=')) {
      const match = s.match(/token=([^&]+)/);
      if (match) s = match[1];
    } else if (s.includes('uid=')) {
      const match = s.match(/uid=([^&]+)/);
      if (match) s = match[1];
    }
    if (s.startsWith('bgl_')) {
      const parts = s.split('_');
      if (parts[1]) return parts[1];
    }
    return s.replace(/[^0-9a-zA-Z_-]/g, '');
  }

  function updateTenantUI(rawTokenOrId) {
    const cleanId = parseUserId(rawTokenOrId);
    const displayVal = rawTokenOrId || '';
    if (tenantInputLic && document.activeElement !== tenantInputLic) tenantInputLic.value = displayVal;
    if (tenantInputDash && document.activeElement !== tenantInputDash) tenantInputDash.value = displayVal;

    if (cleanId) {
      const text = `Conectado ao ID: ${cleanId.length > 14 ? cleanId.slice(0, 14) + '...' : cleanId}`;
      if (tenantStatusTextLic) {
        tenantStatusTextLic.textContent = text;
        tenantStatusTextLic.style.color = 'var(--success)';
      }
      if (tenantDotLic) tenantDotLic.style.background = 'var(--success)';

      if (tenantStatusTextDash) {
        tenantStatusTextDash.textContent = text;
        tenantStatusTextDash.style.color = 'var(--success)';
      }
      if (tenantDotDash) tenantDotDash.style.background = 'var(--success)';
    } else {
      const text = 'Modo Geral (Fila Pública)';
      if (tenantStatusTextLic) {
        tenantStatusTextLic.textContent = text;
        tenantStatusTextLic.style.color = 'var(--text-dim)';
      }
      if (tenantDotLic) tenantDotLic.style.background = 'var(--text-dim)';

      if (tenantStatusTextDash) {
        tenantStatusTextDash.textContent = text;
        tenantStatusTextDash.style.color = 'var(--text-dim)';
      }
      if (tenantDotDash) tenantDotDash.style.background = 'var(--text-dim)';
    }
  }

  function saveTenantId(raw) {
    const cleanId = parseUserId(raw);
    chrome.storage.local.set({
      bglRawToken: raw,
      bglUserId: cleanId
    }, () => {
      updateTenantUI(raw);
      chrome.runtime.sendMessage({ type: 'updateTenantConfig', rawToken: raw, userId: cleanId });
      showToast('✅', cleanId ? 'ID Conectado!' : 'ID Removido', cleanId ? `Jogador: ${cleanId}` : 'Modo Geral Ativo', true);
    });
  }

  chrome.storage.local.get(['bglRawToken', 'bglUserId'], (data) => {
    const tokenOrId = (data && (data.bglRawToken || data.bglUserId)) || '';
    updateTenantUI(tokenOrId);
  });

  if (tenantSaveBtnLic) {
    tenantSaveBtnLic.addEventListener('click', () => {
      saveTenantId((tenantInputLic ? tenantInputLic.value : '').trim());
    });
  }

  if (tenantSaveBtnDash) {
    tenantSaveBtnDash.addEventListener('click', () => {
      saveTenantId((tenantInputDash ? tenantInputDash.value : '').trim());
    });
  }

  if (tenantClearBtn) {
    tenantClearBtn.addEventListener('click', () => {
      if (tenantInputLic) tenantInputLic.value = '';
      if (tenantInputDash) tenantInputDash.value = '';
      saveTenantId('');
    });
  }

  function syncFromSite() {
    showToast('⚡', 'Conectando ao site...', 'Buscando token ativo', true);

    chrome.tabs.query({ url: ['https://bgl-queue.vercel.app/*', 'http://localhost:*/*'] }, (tabs) => {
      if (tabs && tabs.length > 0) {
        const activeTab = tabs[0];
        chrome.tabs.sendMessage(activeTab.id, { type: 'getSiteToken' }, (res) => {
          if (chrome.runtime.lastError || !res || !res.token) {
            chrome.tabs.sendMessage(activeTab.id, { type: 'getSiteToken' });
            showToast('⚠️', 'Faça login no site', 'Entre no painel e tente novamente', false);
          } else {
            saveTenantId(res.token);
          }
        });
      } else {
        chrome.tabs.create({ url: 'https://bgl-queue.vercel.app' });
        showToast('🌐', 'Site aberto!', 'Faça login e clique novamente', true);
      }
    });
  }

  const syncFromSiteBtnLic = document.getElementById('syncFromSiteBtnLic');
  const syncFromSiteBtnDash = document.getElementById('syncFromSiteBtnDash');
  if (syncFromSiteBtnLic) syncFromSiteBtnLic.addEventListener('click', syncFromSite);
  if (syncFromSiteBtnDash) syncFromSiteBtnDash.addEventListener('click', syncFromSite);

  // Escuta token detectado proativamente por site_bridge.js
  chrome.runtime.onMessage.addListener((req) => {
    if (req.type === 'siteTokenAvailable' && req.token) {
      chrome.storage.local.get(['bglRawToken'], (data) => {
        if (!data || !data.bglRawToken) {
          saveTenantId(req.token);
        }
      });
    }
  });

  if (activateBtn) activateBtn.addEventListener('click', activate);

  document.getElementById('pauseOnce')?.addEventListener('click', () => showToast('⏸', 'Paused for this visit', 'Will resume on next page load', true));
  document.getElementById('pauseAlways')?.addEventListener('click', () => showToast('✅', 'Site whitelisted', 'AdBlock paused on this domain', true));
  document.getElementById('whitelist')?.addEventListener('click', () => showToast('⭐', 'Added to favorites', 'Custom rules will be applied', true));
  document.getElementById('removeLicense')?.addEventListener('click', () => {
    chrome.storage.local.set({ licenseValid: false, licenseKey: null }, () => location.reload());
  });

})();
