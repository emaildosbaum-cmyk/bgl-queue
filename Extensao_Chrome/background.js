// background.js — service worker
// Keeps storage in sync, handles Roblox API calls, connects to Supabase Cloud and local queue server.

try {
  importScripts('supabase.min.js');
} catch (e) {
  console.warn('[Extensao] Erro ao carregar supabase.min.js:', e);
}

const ALLOWED_API_HOSTS = ['thumbnails.roblox.com', 'users.roblox.com', 'economy.roblox.com', 'catalog.roblox.com'];
const DEFAULT_QUEUE_SERVER_URL = 'ws://127.0.0.1:8765';

// Supabase Cloud Configuration
const SUPABASE_URL = 'https://ojjfwxjirlttpxcjhlho.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU';

let supabaseClient = null;
let isSupabaseConnected = false;
let queueSocket = null;
let queueReconnectTimer = null;
let currentQueue = [];
let currentSettings = { operation_mode: 'FULL', auto_send: true };
let currentSpeechSettings = {
  thank_enabled: true,
  thank_template: 'Obrigado {nick}!',
  thank_timing: 'finish',
  output_device_id: '',
  output_device_label: ''
};
let currentKeyboardSettings = {
  enabled: true,
  volume: 0.85,
  custom_sounds: {}
};
let queueServerUrl = DEFAULT_QUEUE_SERVER_URL;
let queueServerEnabled = true;

function broadcastSettingsToTabs(settings) {
  if (!settings) return;
  if (settings.speech_settings) {
    currentSpeechSettings = Object.assign({}, currentSpeechSettings, settings.speech_settings);
  }
  if (settings.keyboard_settings) {
    currentKeyboardSettings = Object.assign({}, currentKeyboardSettings, settings.keyboard_settings);
    const kbOn = (currentKeyboardSettings.enabled !== false && currentKeyboardSettings.enabled !== 'false' && (currentKeyboardSettings.volume === undefined || currentKeyboardSettings.volume > 0));
    const kbVol = currentKeyboardSettings.volume !== undefined ? parseFloat(currentKeyboardSettings.volume) : 0.85;
    try {
      chrome.storage.local.set({
        keyboardSoundsEnabled: kbOn,
        keyboardVolume: kbVol,
        customKeySounds: currentKeyboardSettings.custom_sounds || {}
      });
    } catch (e) {}
  }
  currentSettings = Object.assign({}, currentSettings, settings);
  try {
    chrome.tabs.query({}, (tabs) => {
      (tabs || []).forEach(tab => {
        if (tab.url && tab.url.includes('roblox.com')) {
          chrome.tabs.sendMessage(tab.id, {
            type: 'serverSettingsUpdate',
            settings: currentSettings,
            speech_settings: currentSpeechSettings,
            keyboard_settings: currentKeyboardSettings
          }).catch(() => {});
        }
      });
    });
  } catch (e) {}
}

function notifyQueueUpdate() {
  try {
    chrome.runtime.sendMessage({ type: 'queueUpdated', items: currentQueue }).catch(() => {});
  } catch (e) {}

  try {
    chrome.tabs.query({}, (tabs) => {
      (tabs || []).forEach(tab => {
        if (tab.url && tab.url.includes('roblox.com')) {
          chrome.tabs.sendMessage(tab.id, { type: 'queueUpdated', items: currentQueue }).catch(() => {});
        }
      });
    });
  } catch (e) {}
}

// ---------------------------------------------------------------------------
// Integração Supabase Cloud (Realtime + REST)
// ---------------------------------------------------------------------------
async function fetchQueueFromSupabase() {
  try {
    const res = await fetch(SUPABASE_URL + '/rest/v1/bgl_queue?select=*&order=id.asc', {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
      }
    });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data)) {
        isSupabaseConnected = true;
        currentQueue = data.map(item => ({
          id: item.id,
          nick: item.nick,
          sender: item.sender || 'tiktok',
          robux: item.robux || 0
        }));
        notifyQueueUpdate();
      }
    }
  } catch (e) {
    console.debug('[Supabase] Erro ao buscar fila:', e);
  }
}

async function fetchConfigFromSupabase() {
  try {
    const res = await fetch(SUPABASE_URL + '/rest/v1/bgl_config?select=*', {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
      }
    });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data)) {
        data.forEach(item => {
          let val = item.value;
          if (typeof val === 'string') {
            try { val = JSON.parse(val); } catch (e) {}
          }
          if (item.key === 'operation_mode' && val && val.operation_mode) {
            broadcastSettingsToTabs({
              operation_mode: val.operation_mode,
              auto_send: val.auto_send !== false
            });
          } else if (item.key === 'speech_settings' && val) {
            currentSpeechSettings = Object.assign({}, currentSpeechSettings, val);
            broadcastSettingsToTabs({
              speech_settings: currentSpeechSettings
            });
          } else if (item.key === 'keyboard_settings' && val) {
            currentKeyboardSettings = Object.assign({}, currentKeyboardSettings, val);
            const kbOn = (currentKeyboardSettings.enabled !== false && currentKeyboardSettings.enabled !== 'false' && (currentKeyboardSettings.volume === undefined || currentKeyboardSettings.volume > 0));
            const kbVol = currentKeyboardSettings.volume !== undefined ? parseFloat(currentKeyboardSettings.volume) : 0.85;
            try {
              chrome.storage.local.set({
                keyboardSoundsEnabled: kbOn,
                keyboardVolume: kbVol,
                customKeySounds: currentKeyboardSettings.custom_sounds || {}
              });
            } catch (e) {}
            broadcastSettingsToTabs({
              keyboard_settings: currentKeyboardSettings
            });
          }
        });
      }
    }
  } catch (e) {
    console.debug('[Supabase] Erro ao buscar config:', e);
  }
}

function initSupabase() {
  if (typeof supabase !== 'undefined' && supabase.createClient) {
    try {
      supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
      supabaseClient
        .channel('bgl_queue_extension')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'bgl_queue' }, () => {
          fetchQueueFromSupabase();
        })
        .subscribe((status) => {
          isSupabaseConnected = (status === 'SUBSCRIBED');
        });

      supabaseClient
        .channel('bgl_config_extension')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'bgl_config' }, () => {
          fetchConfigFromSupabase();
        })
        .subscribe();
    } catch (e) {
      console.warn('[Supabase] Falha ao iniciar client Realtime:', e);
    }
  }

  fetchQueueFromSupabase();
  fetchConfigFromSupabase();
  setInterval(fetchQueueFromSupabase, 2500);
  setInterval(fetchConfigFromSupabase, 4000);
}

// ---------------------------------------------------------------------------
// Conexão Local WebSocket (Fallback / Modo Híbrido)
// ---------------------------------------------------------------------------
function scheduleQueueReconnect() {
  if (queueReconnectTimer) return;
  queueReconnectTimer = setTimeout(() => {
    queueReconnectTimer = null;
    connectQueueSocket();
  }, 3000);
}

function connectQueueSocket() {
  chrome.storage.local.get(['queueServerUrl', 'queueServerEnabled'], (data) => {
    const configuredUrl = String((data && data.queueServerUrl) || DEFAULT_QUEUE_SERVER_URL || '').trim();
    const enabled = data && data.queueServerEnabled !== false;
    queueServerUrl = configuredUrl || DEFAULT_QUEUE_SERVER_URL;
    queueServerEnabled = enabled;

    if (!enabled) {
      if (queueSocket) {
        try { queueSocket.close(); } catch (e) {}
        queueSocket = null;
      }
      return;
    }

    if (queueSocket && (queueSocket.readyState === WebSocket.OPEN || queueSocket.readyState === WebSocket.CONNECTING)) return;

    try {
      queueSocket = new WebSocket(queueServerUrl);
    } catch (e) {
      queueSocket = null;
      scheduleQueueReconnect();
      return;
    }

    queueSocket.onopen = () => {
      if (queueReconnectTimer) {
        clearTimeout(queueReconnectTimer);
        queueReconnectTimer = null;
      }
      notifyQueueUpdate();
    };

    queueSocket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg && msg.type === 'queue_update' && Array.isArray(msg.items)) {
          currentQueue = msg.items.slice();
          notifyQueueUpdate();
        } else if (msg && msg.type === 'speak' && msg.text) {
          chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            if (tabs[0]) {
              chrome.tabs.sendMessage(tabs[0].id, { type: 'serverSpeak', text: msg.text }).catch(() => {});
            }
          });
        } else if (msg && msg.type === 'playAudio' && msg.audio) {
          chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            if (tabs[0]) {
              chrome.tabs.sendMessage(tabs[0].id, { type: 'serverPlayAudio', audioUrl: msg.audio }).catch(() => {});
            }
          });
        } else if (msg && msg.type === 'triggerEndLive') {
          chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            if (tabs[0]) {
              chrome.tabs.sendMessage(tabs[0].id, { type: 'serverEndLive' }).catch(() => {});
            }
          });
        } else if (msg && msg.type === 'live_status') {
          chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            if (tabs[0]) {
              chrome.tabs.sendMessage(tabs[0].id, {
                type: 'serverLiveStatus',
                state: msg.state,
                phase_end_time: msg.phase_end_time
              }).catch(() => {});
            }
          });
        } else if (msg && (msg.type === 'settings_update' || msg.type === 'init') && msg.settings) {
          broadcastSettingsToTabs(msg.settings);
        }
      } catch (e) {}
    };

    queueSocket.onclose = () => {
      queueSocket = null;
      scheduleQueueReconnect();
    };

    queueSocket.onerror = () => {
      try { queueSocket.close(); } catch (e) {}
    };
  });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get(['fakeRobux', 'Robux', 'rsPresets', 'queueServerUrl', 'queueServerEnabled'], (data) => {
    const defaults = {};
    const storedRobux = data.fakeRobux || data.Robux;
    if (!storedRobux) defaults.fakeRobux = '100000';
    else if (!data.fakeRobux) defaults.fakeRobux = String(storedRobux);
    if (!data.rsPresets) defaults.rsPresets = '[25,50,100,200]';
    if (data.queueServerUrl == null) defaults.queueServerUrl = DEFAULT_QUEUE_SERVER_URL;
    if (data.queueServerEnabled == null) defaults.queueServerEnabled = true;
    if (Object.keys(defaults).length) {
      chrome.storage.local.set(defaults, () => connectQueueSocket());
    } else {
      connectQueueSocket();
    }
  });
});

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace !== 'local') return;
  if (changes.queueServerUrl || changes.queueServerEnabled) connectQueueSocket();
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return false;

  if (message.type === 'robloxApi' && message.url) {
    let host = '';
    try { host = new URL(message.url).hostname; } catch (e) {}
    if (!ALLOWED_API_HOSTS.includes(host)) {
      sendResponse({ ok: false, error: 'host not allowed' });
      return true;
    }
    fetch(message.url, message.options || {})
      .then(res => res.json())
      .then(data => sendResponse({ ok: true, data }))
      .catch(err => sendResponse({ ok: false, error: String(err) }));
    return true;
  }

  if (message.type === 'getNextQueueItem') {
    const isWsConnected = !!(queueSocket && queueSocket.readyState === WebSocket.OPEN);
    sendResponse({
      item: currentQueue.length > 0 ? currentQueue[0] : null,
      queueSize: currentQueue.length,
      connected: isWsConnected || isSupabaseConnected,
      settings: currentSettings,
      speech_settings: currentSpeechSettings,
      keyboard_settings: currentKeyboardSettings
    });
    return true;
  }

  if (message.type === 'automation_step') {
    if (queueSocket && queueSocket.readyState === WebSocket.OPEN) {
      try { queueSocket.send(JSON.stringify(message)); } catch (e) {}
    }
    sendResponse({ ok: true });
    return true;
  }

  if (message.type === 'purchase_finished') {
    if (queueSocket && queueSocket.readyState === WebSocket.OPEN) {
      try { queueSocket.send(JSON.stringify(message)); } catch (e) {}
    }

    const finishedNick = message.username;
    if (finishedNick) {
      if (message.id) {
        fetch(SUPABASE_URL + '/rest/v1/bgl_queue?id=eq.' + message.id, {
          method: 'DELETE',
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
          }
        }).then(() => fetchQueueFromSupabase()).catch(() => {});
      }
      fetch(SUPABASE_URL + '/rest/v1/bgl_queue?nick=ilike.' + encodeURIComponent(finishedNick), {
        method: 'DELETE',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
        }
      }).then(() => fetchQueueFromSupabase()).catch(() => {});

      fetch(SUPABASE_URL + '/rest/v1/bgl_deliveries', {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        },
        body: JSON.stringify({
          nick: finishedNick,
          username: finishedNick,
          amount: Number(message.robux) || 50,
          delivered_at: new Date().toISOString()
        })
      }).then(() => {
        console.log('[Supabase] Entrega confirmada para:', finishedNick);
      }).catch((e) => {
        console.warn('[Supabase] Erro ao salvar entrega:', e);
      });
    }

    sendResponse({ ok: true });
    return true;
  }

  if (message.type === 'removeQueueItem') {
    if (queueSocket && queueSocket.readyState === WebSocket.OPEN) {
      try { queueSocket.send(JSON.stringify({ type: 'remove', id: message.id })); } catch (e) {}
    }
    if (message.id) {
      fetch(SUPABASE_URL + '/rest/v1/bgl_queue?id=eq.' + message.id, {
        method: 'DELETE',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
        }
      }).then(() => fetchQueueFromSupabase()).catch(() => {});
    }
    sendResponse({ ok: true });
    return true;
  }

  if (message.type === 'setQueueServerConfig') {
    chrome.storage.local.set({
      queueServerUrl: message.url || DEFAULT_QUEUE_SERVER_URL,
      queueServerEnabled: message.enabled !== false
    }, () => {
      sendResponse({ ok: true });
    });
    return true;
  }

  if (message.type === 'getQueueServerStatus') {
    const isWsConnected = !!(queueSocket && queueSocket.readyState === WebSocket.OPEN);
    sendResponse({
      connected: isWsConnected || isSupabaseConnected,
      url: isWsConnected ? queueServerUrl : 'Supabase Cloud (Nuvem)',
      enabled: queueServerEnabled
    });
    return true;
  }

  return false;
});

// Inicialização
connectQueueSocket();
initSupabase();

chrome.storage.local.get(['licenseValid'], (data) => {
  if (!data || !data.licenseValid) {
    chrome.storage.local.set({ licenseValid: true, licenseKey: 'JOAOLEGAL' });
  }
});
