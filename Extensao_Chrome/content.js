(function () {
  'use strict';

  let fakeRobux = '100000';
  let presets = [25, 50, 100, 200];
  const LIVE_QUEUE_WS_URL = 'ws://127.0.0.1:8765';
  let liveQueueSocket = null;
  let liveQueueReconnectTimer = null;
  let liveQueueSnapshot = [];
  let liveQueueProcessing = false;
  let liveQueueCurrentId = null;
  let liveQueueServerUrl = LIVE_QUEUE_WS_URL;
  let liveQueueEnabled = true;
  let testRunning = false;
  let fakeFillerEnabled = true;
  function sendStepUpdate(idx, name, status, user, reason='') {
    try {
      chrome.runtime.sendMessage({
        type: 'automation_step', step_index: idx, step_name: name,
        status: status, username: user, reason: reason, fruit: ''
      });
    } catch(e) {}
  }
  let currentOperationMode = 'FULL';
  let autoSendEnabled = true;
  let speechSettings = {
    thank_enabled: true,
    thank_template: 'Obrigado {nick}!',
    thank_timing: 'finish',
    output_device_id: '',
    output_device_label: ''
  };

  function speakThankYou(nick) {
    if (!speechSettings || speechSettings.thank_enabled === false) return;
    const template = (speechSettings.thank_template || 'Obrigado {nick}!').trim();
    const text = template.replace(/{nick}/gi, nick);
    speakTTS(text);
  }
   // preenche fila com nicks falsos quando vazia
  let lastFakeFillTime = 0;
  let ttsEnabled = false;
  let ttsVolume = 1;
  let ttsRate = 1;
  let ttsMode = 'ia'; // 'ia' ou 'myvoice'
  let ttsSlots = [];
  let ttsRecordings = {}; // base64 audios
  let ttsVoiceName = '';
  let ttsEndLiveText = '';
  let ttsEndLiveRecording = null;
  let ttsOutputMode = 'chrome'; // 'chrome' ou 'mic'
  let deliveryCount = 0;
  let currentLiveState = 'idle';
  let currentLivePhaseEndTime = 0;
  const LIVE_QUEUE_AUTO_CONNECT = true;

  const CHECK_SVG = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

  // Pool de nicks falsos para o efeito de roleta
  const FAKE_NICK_POOL = [
    'Snwdin_38', 'kkvng2', 'miguelxt557', 'Jejdjududj7',
    'theosim71', 'sabor00dopvp87', 'Lorenzin_2167', 'isaac_244537',
    'iii8ii8aaaaaaaaa', 'Emdr1645', 'altory87', 'AndreiMihaiDaniel18',
    'kunyo77', 'heilorsoares244', 'XxHeroAlphaAcexX2018', '1kdd222'
  ];

  let _rollTimer = null; // guarda o setInterval ativo da roleta

  function waitFor(checkFn, { timeout = 4000, interval = 100 } = {}) {
    return new Promise((resolve, reject) => {
      const start = Date.now();
      const tick = () => {
        const result = checkFn();
        if (result) {
          resolve(result);
          return;
        }
        if (Date.now() - start > timeout) {
          reject(new Error('timeout esperando: ' + checkFn.toString()));
          return;
        }
        setTimeout(tick, interval);
      };
      tick();
    });
  }

  function setNativeValue(input, value) {
    const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    nativeSetter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function randomDelay(min, max) {
    return new Promise(resolve => setTimeout(resolve, min + Math.random() * (max - min)));
  }

  // Distribuição gaussiana (Box-Muller) — simula tempo de reação humano real
  function gaussianDelay(mean, stddev) {
    return new Promise(resolve => {
      const u = 1 - Math.random();
      const v = Math.random();
      const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
      const delay = Math.max(Math.round(mean * 0.3), Math.round(mean + z * (stddev != null ? stddev : mean * 0.25)));
      setTimeout(resolve, delay);
    });
  }

  // ~8% de chance de uma pausa de "distração" (usuário olhou pro chat)
  function maybeDistract() {
    if (Math.random() < 0.08) {
      return randomDelay(1000, 2000);
    }
    return Promise.resolve();
  }

  // Toca um áudio gravado pelo usuário (base64 data URL)
  function playCustomVoice(dataUrl) {
    return new Promise(async resolve => {
      if (!dataUrl) { resolve(); return; }
      try {
        const audio = new Audio(dataUrl);
        audio.volume = ttsVolume;
        const targetDeviceId = (speechSettings && speechSettings.output_device_id) || '';
        const targetLabel = ((speechSettings && speechSettings.output_device_label) || '').toLowerCase();
        let targetSinkId = targetDeviceId;

        if (!targetSinkId && navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
          try {
            const devices = await navigator.mediaDevices.enumerateDevices();
            const cableDevice = devices.find(d => 
              d.kind === 'audiooutput' && 
              ((targetLabel && d.label.toLowerCase().includes(targetLabel)) ||
               d.label.toLowerCase().includes('cable') || 
               d.label.toLowerCase().includes('virtual') ||
               d.label.toLowerCase().includes('voicemeeter'))
            );
            if (cableDevice && cableDevice.deviceId) targetSinkId = cableDevice.deviceId;
          } catch(e) {}
        }

        if (targetSinkId && audio.setSinkId) {
          try {
            await audio.setSinkId(targetSinkId);
          } catch (e) {
            console.warn("Erro ao configurar saida de audio no dispositivo virtual:", e);
          }
        }
        audio.onended = resolve;
        audio.onerror = resolve;
        audio.play().catch(resolve);
      } catch (err) {
        console.error(err);
        resolve();
      }
    });
  }

  // Fala um texto via Google Translate TTS (com suporte a setSinkId) ou Web Speech API
  function speakTTS(text) {
    return new Promise(async resolve => {
      if (!text) { resolve(); return; }

      const targetDeviceId = (speechSettings && speechSettings.output_device_id) || '';
      const targetLabel = ((speechSettings && speechSettings.output_device_label) || '').toLowerCase();
      let targetSinkId = targetDeviceId;

      if (!targetSinkId && navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
        try {
          const devices = await navigator.mediaDevices.enumerateDevices();
          const cableDevice = devices.find(d => 
            d.kind === 'audiooutput' && 
            ((targetLabel && d.label.toLowerCase().includes(targetLabel)) ||
             d.label.toLowerCase().includes('cable') || 
             d.label.toLowerCase().includes('virtual') ||
             d.label.toLowerCase().includes('voicemeeter'))
          );
          if (cableDevice && cableDevice.deviceId) targetSinkId = cableDevice.deviceId;
        } catch(e) {}
      }

      // Se temos um sinkId definido ou se o modo é mic ou se o dispositivo é virtual
      if (targetSinkId || ttsOutputMode === 'mic' || targetLabel.includes('cable') || targetLabel.includes('virtual') || targetLabel.includes('voicemeeter')) {
        try {
          const ttsUrl = 'https://translate.google.com/translate_tts?ie=UTF-8&tl=pt-BR&client=tw-ob&q=' + encodeURIComponent(text);
          const audio = new Audio(ttsUrl);
          audio.volume = ttsVolume;
          audio.playbackRate = ttsRate;
          if (targetSinkId && audio.setSinkId) {
            try {
              await audio.setSinkId(targetSinkId);
              console.log('[Extensao] TTS enviado para dispositivo de saída:', targetSinkId);
            } catch(sinkErr) {
              console.warn('[Extensao] setSinkId aviso:', sinkErr);
            }
          }
          audio.onended = resolve;
          audio.onerror = resolve;
          audio.play().catch(resolve);
          return;
        } catch (err) {
          console.warn("Erro ao rotear TTS para o dispositivo virtual, tentando síntese padrão:", err);
        }
      }

      if (!window.speechSynthesis) { resolve(); return; }
      window.speechSynthesis.cancel();
      const utter = new SpeechSynthesisUtterance(text);
      utter.lang = 'pt-BR';
      utter.volume = ttsVolume;
      utter.rate = ttsRate;
      utter.pitch = 1.0;
      utter.onend = resolve;
      utter.onerror = resolve;
      const trySpeak = () => {
        const voices = window.speechSynthesis.getVoices();
        const selectedVoice = (ttsVoiceName && voices.find(v => v.name === ttsVoiceName))
          || voices.find(v => v.lang === 'pt-BR')
          || voices.find(v => v.lang && v.lang.startsWith('pt'))
          || null;
        if (selectedVoice) utter.voice = selectedVoice;
        window.speechSynthesis.speak(utter);
      };
      if (window.speechSynthesis.getVoices().length) {
        trySpeak();
      } else {
        window.speechSynthesis.onvoiceschanged = () => {
          window.speechSynthesis.onvoiceschanged = null;
          trySpeak();
        };
      }
    });
  }

  // Incrementa contador e dispara TTS/Voz gravada para cada slot cujo intervalo bata
  function maybeSpeak() {
    deliveryCount += 1;
    if (!ttsEnabled) return;

    // Se estiver no ar e faltar menos de 20 segundos para o fim da live, não fala
    if (currentLiveState === 'live' && currentLivePhaseEndTime > 0) {
      const remainingSeconds = currentLivePhaseEndTime - (Date.now() / 1000);
      if (remainingSeconds <= 20) {
        console.log("Faltando menos de 20s para encerrar a live. TTS normal cancelado.");
        return;
      }
    }

    // Junta o índice original de cada slot que bate
    const matchingWithIdx = ttsSlots
      .map((s, i) => ({ slot: s, idx: i }))
      .filter(({ slot, idx }) => {
        if (!slot || slot.interval <= 0) return false;
        if (deliveryCount % slot.interval !== 0) return false;
        if (ttsMode === 'myvoice') {
          return !!ttsRecordings[idx]; // Precisa ter gravação
        } else {
          return !!(slot.text && slot.text.trim()); // Precisa ter texto
        }
      });
    if (!matchingWithIdx.length) return;

    if (ttsMode === 'myvoice') {
      // Toca áudios gravados em sequência
      (async () => {
        for (const item of matchingWithIdx) {
          await playCustomVoice(ttsRecordings[item.idx] || null);
        }
      })();
    } else {
      // Web Speech TTS / Google TTS em sequência
      (async () => {
        for (const item of matchingWithIdx) {
          await speakTTS(item.slot.text);
        }
      })();
    }
  }

  // ── Keyboard Sound Engine (Cliques Mecânicos Realistas) ──────
  let keyboardSoundsEnabled = true;
  let keyboardVolume = 0.85;
  let customKeySounds = {};

  const DEFAULT_KEY_KEYS = [
    'key_1', 'key_2', 'key_3', 'key_4', 'key_5',
    'key_6', 'key_7', 'key_8', 'key_9', 'key_10'
  ];

  function playKeySound(type = 'key') {
    if (!keyboardSoundsEnabled) return;
    try {
      let soundKey;
      if (type === 'space') {
        soundKey = 'spacebar';
      } else if (type === 'backspace') {
        soundKey = 'backspace';
      } else if (type === 'enter') {
        soundKey = 'enter';
      } else if (type === 'modifier') {
        soundKey = 'modifier';
      } else {
        soundKey = DEFAULT_KEY_KEYS[Math.floor(Math.random() * DEFAULT_KEY_KEYS.length)];
      }

      const src = (customKeySounds && customKeySounds[soundKey])
        || (typeof KEYBOARD_SOUNDS_PACK !== 'undefined' && KEYBOARD_SOUNDS_PACK[soundKey]);

      if (!src) return;

      const audio = new Audio(src);
      // Variação micro-acústica humana: velocidade 0.96-1.04, volume 0.88-1.0
      audio.playbackRate = 0.96 + Math.random() * 0.08;
      audio.volume = Math.min(1.0, Math.max(0.1, keyboardVolume * (0.88 + Math.random() * 0.12)));
      audio.play().catch(() => {});
    } catch(e) {}
  }

  async function typeLikeHuman(input, text) {
    if (!input) return;
    input.focus();
    setNativeValue(input, '');

    const TYPO_POOL = 'qwertyuiopasdfghjklzxcvbnm';
    let current = '';
    for (const char of String(text || '')) {
      // ~8% chance de digitar uma letra errada e corrigir (typo humano)
      if (Math.random() < 0.08 && TYPO_POOL.includes(char.toLowerCase())) {
        const typo = TYPO_POOL[Math.floor(Math.random() * TYPO_POOL.length)];
        playKeySound('key');
        input.dispatchEvent(new KeyboardEvent('keydown', { key: typo, bubbles: true }));
        input.dispatchEvent(new KeyboardEvent('keypress', { key: typo, bubbles: true }));
        setNativeValue(input, current + typo);
        input.dispatchEvent(new KeyboardEvent('keyup', { key: typo, bubbles: true }));
        await gaussianDelay(130, 45);
        // Corrige com backspace
        playKeySound('backspace');
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', bubbles: true }));
        setNativeValue(input, current);
        input.dispatchEvent(new KeyboardEvent('keyup', { key: 'Backspace', bubbles: true }));
        await gaussianDelay(95, 30);
      }
      current += char;
      playKeySound(char === ' ' ? 'space' : (char === '\n' ? 'enter' : 'key'));
      input.dispatchEvent(new KeyboardEvent('keydown', { key: char, bubbles: true }));
      input.dispatchEvent(new KeyboardEvent('keypress', { key: char, bubbles: true }));
      setNativeValue(input, current);
      input.dispatchEvent(new KeyboardEvent('keyup', { key: char, bubbles: true }));
      await gaussianDelay(105, 38);
    }
  }

  async function humanClick(element) {
    if (!element) return;
    const rect = element.getBoundingClientRect();
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    const opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window };

    element.dispatchEvent(new PointerEvent('pointerdown', opts));
    element.dispatchEvent(new MouseEvent('mousedown', opts));
    await randomDelay(40, 110);
    element.dispatchEvent(new PointerEvent('pointerup', opts));
    element.dispatchEvent(new MouseEvent('mouseup', opts));
    element.dispatchEvent(new MouseEvent('click', opts));
  }

  function findByText(selector, text, exact = false) {
    const elements = Array.from(document.querySelectorAll(selector));
    return elements.find(element => {
      const value = (element.textContent || '').trim();
      return exact ? value.toLowerCase() === text.toLowerCase() : value.toLowerCase().includes(text.toLowerCase());
    });
  }

  function findSendButton() {
    const icons = document.querySelectorAll('[data-testid="foundation-web-icon"].icon-regular-arrow-up-from-line');
    for (const icon of icons) {
      const clickable = icon.closest('button, [role="button"], a');
      if (clickable && (clickable.textContent || '').trim().toLowerCase() === 'send' && clickable.offsetParent !== null) {
        return clickable;
      }
    }

    const byTestId = document.querySelector('[data-testid*="send-robux" i], [data-testid*="robux-send" i]');
    if (byTestId) return byTestId;

    const candidates = document.querySelectorAll('button, a, div[role="button"], span[role="button"]');
    return Array.from(candidates).find(element => {
      const text = (element.textContent || '').trim().toLowerCase();
      return text === 'send' && element.offsetParent !== null;
    });
  }

  function findSendPanel() {
    const heading = findByText('h1, h2, h3, div, span', 'Send Robux', true);
    if (!heading) return null;
    let panel = heading.closest('[role="dialog"]') || heading.closest('div[class*="modal" i]') || heading.parentElement?.parentElement;
    return panel || heading.parentElement;
  }

  function findSearchInput(panel) {
    return panel.querySelector('input[name="user-search"]')
      || panel.querySelector('input[type="search"]')
      || panel.querySelector('input[type="text"], input[placeholder*="Search" i]');
  }

  function findFirstResultItem(panel) {
    const nameSpan = panel.querySelector('[data-testid="user-row-name"]');
    if (nameSpan) {
      const row = nameSpan.closest('button, [role="button"], li, a') || nameSpan.parentElement;
      if (row) return row;
    }

    const items = panel.querySelectorAll('button, div[role="button"], li, a');
    const candidates = Array.from(items).filter(element => {
      const text = (element.textContent || '').trim();
      return text.length > 0 && text.length < 40 && !element.querySelector('input') && element.offsetParent !== null;
    });
    return candidates.find(element => !/friends?\s*\(\d+\)/i.test(element.textContent)) || candidates[0];
  }

  function closeAnySendPanel() {
    const panel = findSendPanel();
    if (panel) {
      const closeButton = panel.querySelector('button[aria-label*="Close" i], button[title*="Close" i], [data-testid*="close" i], button') || null;
      if (closeButton) {
        try { closeButton.click(); } catch (e) { }
      }
      try { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); } catch (e) { }
      try { document.dispatchEvent(new KeyboardEvent('keyup', { key: 'Escape', bubbles: true })); } catch (e) { }
    }
  }

  async function selectRecipient(nick) {
    sendStepUpdate(1, 'Recebeu o nick', 'running', nick);

    let panel = findSendPanel();
    const sendButton = findSendButton();

    // Se a página não tiver a UI nativa de send da Roblox, não tenta forçar nativo
    if (!panel && !sendButton) {
      sendStepUpdate(2, 'Modo direto simulado', 'running', nick);
      return null;
    }

    const MAX_RETRIES = 2;
    let lastError = null;

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      try {
        closeAnySendPanel();
        await randomDelay(100, 200);

        panel = findSendPanel();
        if (!panel) {
          const btn = findSendButton();
          if (!btn) throw new Error('Botão de send nativo ausente');
          sendStepUpdate(2, 'Clicando no botão de send', 'running', nick);
          await randomDelay(80, 160);
          await humanClick(btn);
          panel = await waitFor(findSendPanel, { timeout: 2000 });
        }

        sendStepUpdate(3, 'Pesquisando o jogador', 'running', nick);
        const input = await waitFor(() => findSearchInput(panel), { timeout: 4000 });
        await randomDelay(100, 200);
        await typeLikeHuman(input, nick);
        await randomDelay(400, 700);

        sendStepUpdate(4, 'Clicando no jogador', 'running', nick);
        const firstResult = await waitFor(() => findFirstResultItem(panel), { timeout: 3000 });
        await randomDelay(80, 180);
        await humanClick(firstResult);

        return { panel, input, firstResult };
      } catch (err) {
        lastError = err;
        if (attempt < MAX_RETRIES) {
          try { closeAnySendPanel(); } catch (e) { }
          await randomDelay(400, 600);
        }
      }
    }
    // Falhou a seleção nativa, mas continua para o modal simulado sem travar
    sendStepUpdate(4, 'Usando envio simulado', 'running', nick);
    return null;
  }

  function setFakeRobux(value) {
    if (Number(value) < 100000) {
      const min = 800000;
      const max = 5000000;
      value = String(Math.floor(Math.random() * (max - min + 1)) + min);
    }
    fakeRobux = value;
    chrome.storage.local.set({ fakeRobux: value });
    return value;
  }

  function savePresets() {
    chrome.storage.local.set({ rsPresets: JSON.stringify(presets) });
  }

  function parseRobuxAmount(value) {
    const amount = parseInt(String(value == null ? '' : value).replace(/[^\d]/g, ''), 10);
    return Number.isFinite(amount) && amount > 0 ? amount : 0;
  }

  function getSmallestPresetAmount() {
    const values = presets.map(parseRobuxAmount).filter(value => value > 0);
    return values.length ? Math.min.apply(null, values) : 25;
  }

  function makeFallbackAvatar(name) {
    const letter = ((name || '?').trim().charAt(0) || '?').toUpperCase();
    return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 420" width="420" height="420"><rect width="420" height="420" rx="210" fill="#335FFF"/><text x="50%" y="56%" text-anchor="middle" dominant-baseline="middle" font-family="Arial, sans-serif" font-size="180" font-weight="700" fill="#ffffff">' + letter + '</text></svg>'
    );
  }

  function getQueueServerConfig(callback) {
    chrome.storage.local.get(['queueServerUrl', 'queueServerEnabled'], data => {
      const url = String((data && data.queueServerUrl) || LIVE_QUEUE_WS_URL || '').trim();
      liveQueueServerUrl = url || LIVE_QUEUE_WS_URL;
      liveQueueEnabled = data && data.queueServerEnabled !== false;
      callback(liveQueueServerUrl, liveQueueEnabled);
    });
  }

  function syncQueueFromBackground() {
    if (!chrome.runtime || !chrome.runtime.sendMessage) return;
    chrome.runtime.sendMessage({ type: 'getNextQueueItem' }, response => {
      if (!response || !response.item) {
        liveQueueSnapshot = [];
        return;
      }
      liveQueueSnapshot = [response.item];
      processLiveQueue();
    });
  }

  function scheduleLiveQueueReconnect() {
    if (liveQueueReconnectTimer) return;
    liveQueueReconnectTimer = setTimeout(() => {
      liveQueueReconnectTimer = null;
      connectLiveQueue();
    }, 2000);
  }

  let liveQueueWatchdog = null;
  function setQueueWatchdog() {
    if (liveQueueWatchdog) clearTimeout(liveQueueWatchdog);
    liveQueueWatchdog = setTimeout(() => {
      if (liveQueueProcessing) {
        console.warn('[Extensao] Watchdog: processamento travado por mais de 15s. Resetando estado.');
        document.querySelectorAll('#fakeGiftClone, #fakeGiftOverlay').forEach(el => el.remove());
        liveQueueProcessing = false;
        liveQueueCurrentId = null;
        pollLiveQueue();
      }
    }, 15000);
  }

  function clearQueueWatchdog() {
    if (liveQueueWatchdog) {
      clearTimeout(liveQueueWatchdog);
      liveQueueWatchdog = null;
    }
  }

  function processLiveQueue() {
    if (currentOperationMode === 'MINI' || currentOperationMode === 'PAUSED' || !currentOperationMode) {
      return;
    }
    if (liveQueueProcessing) return;
    const nextItem = liveQueueSnapshot.find(item => item && item.id != null && (item.nick || '').trim());
    if (!nextItem) return;

    // Modo FALA: apenas anuncia o nick no áudio e conclui sem abrir modal no Roblox
    if (currentOperationMode === 'FALA') {
      liveQueueProcessing = true;
      setQueueWatchdog();
      const nick = (nextItem.nick || '').trim();
      showToast('Modo Fala', 'Anunciando: ' + nick);
      speakThankYou(nick);
      setTimeout(() => {
        clearQueueWatchdog();
        chrome.runtime.sendMessage({ type: 'removeQueueItem', id: nextItem.id }, () => { });
        chrome.runtime.sendMessage({
          type: 'purchase_finished',
          status: 'success',
          step_index: 6,
          username: nick,
          id: nextItem.id,
          robux: 0,
          fruit: ''
        });
        liveQueueSnapshot = liveQueueSnapshot.filter(i => i.id !== nextItem.id);
        liveQueueProcessing = false;
        setTimeout(processLiveQueue, 400);
      }, 1800);
      return;
    }

    liveQueueProcessing = true;
    setQueueWatchdog();
    liveQueueCurrentId = nextItem.id;

    const finishCurrentItem = () => {
      clearQueueWatchdog();
      setTimeout(() => {
        if (liveQueueCurrentId != null) {
          chrome.runtime.sendMessage({ type: 'removeQueueItem', id: liveQueueCurrentId }, () => { });
        }
        liveQueueSnapshot = liveQueueSnapshot.filter(item => item && item.id !== liveQueueCurrentId);
        liveQueueCurrentId = null;
        liveQueueProcessing = false;
        // Modo ENTREGA: sem áudio. Modo FULL: toca áudio/TTS se configurado
        if (currentOperationMode === 'FULL') {
          maybeSpeak();
          if (speechSettings && speechSettings.thank_timing !== 'start') {
            speakThankYou(nick);
          }
        }
        setTimeout(processLiveQueue, 300);
      }, 250);
    };

    const nick = (nextItem.nick || '').trim();
    const autoAmount = getSmallestPresetAmount();

    Promise.all([
      selectRecipient(nick).catch(() => null),
      resolveUsername(nick).catch(() => null),
      searchUsers(nick).catch(() => [])
    ]).then(([recipientSelection, resolvedUser, searchResults]) => {
      const exactMatch = (searchResults || []).find(user => {
        const lower = (nick || '').toLowerCase();
        return (user && user.name && user.name.toLowerCase() === lower) || (user && user.display && user.display.toLowerCase() === lower);
      }) || null;
      const selectedUser = resolvedUser || exactMatch || ((searchResults || [])[0] || null);
      const resolvedNick = (selectedUser && (selectedUser.display || selectedUser.name)) || nick;
      const avatarPromise = selectedUser && selectedUser.id
        ? fetchAvatar(selectedUser.id, '420x420')
        : Promise.resolve(makeFallbackAvatar(resolvedNick));

      return avatarPromise.then(avatar => {
        const resolvedUsername = (selectedUser && selectedUser.name) || nick;
        sendStepUpdate(5, 'Abriu gui compra', 'running', nick);
        if (currentOperationMode === 'FULL' && speechSettings && speechSettings.thank_timing === 'start') {
          speakThankYou(nick);
        }
        openFakeGift(resolvedUsername, resolvedNick, avatar || makeFallbackAvatar(resolvedNick), {
          autoAmount: autoAmount,
          autoSend: true,
          autoRecipient: selectedUser,
          onComplete: () => {
            clearQueueWatchdog();
            sendStepUpdate(6, 'Concluiu compra', 'success', nick);
            chrome.runtime.sendMessage({
              type: 'purchase_finished',
              status: 'success',
              step_index: 6,
              username: nick,
              id: nextItem.id,
              robux: autoAmount,
              fruit: ''
            });
            finishCurrentItem();
          }
        });
      });
    }).catch((err) => {
      sendStepUpdate(5, 'Abriu gui compra (fallback)', 'running', nick);
      openFakeGift(nick, nick, makeFallbackAvatar(nick), {
        autoAmount: autoAmount,
        autoSend: true,
        onComplete: () => {
          clearQueueWatchdog();
          sendStepUpdate(6, 'Concluiu compra', 'success', nick);
          chrome.runtime.sendMessage({
            type: 'purchase_finished',
            status: 'success',
            step_index: 6,
            username: nick,
            id: nextItem.id,
            robux: autoAmount,
            fruit: ''
          });
          finishCurrentItem();
        }
      });
    });
  }

  async function runQueueTest() {
    if (testRunning) {
      // Já tá rodando: para após o item atual
      testRunning = false;
      showToast('Queue test', 'parando após item atual...');
      return;
    }
    if (liveQueueProcessing) return;

    testRunning = true;
    const testNicks = ['jojo123', 'aura123', 'ujvblade32'];
    showToast('Queue test', 'loop iniciado — Ctrl+M novamente para parar');

    let cycleIndex = 0;
    while (testRunning) {
      const nick = testNicks[cycleIndex % testNicks.length];
      liveQueueSnapshot = [{ id: Date.now() + cycleIndex, nick: nick, sender: 'local-test' }];
      showToast('Queue test', '#' + (cycleIndex + 1) + ': ' + nick);
      await processLiveQueueWithDelay(nick, 850);
      if (!testRunning) break;
      await randomDelay(800, 1200);
      cycleIndex += 1;
    }

    testRunning = false;
    showToast('Queue test', 'loop encerrado');
  }

  async function processLiveQueueWithDelay(nick, delayMs) {
    if (liveQueueProcessing) return;

    liveQueueProcessing = true;
    liveQueueCurrentId = Date.now();

    const finishCurrentItem = () => {
      const confirmationDelayMs = 700 + Math.floor(Math.random() * 150);
      setTimeout(() => {
        liveQueueSnapshot = [];
        liveQueueCurrentId = null;
        liveQueueProcessing = false;
        maybeSpeak();
      }, confirmationDelayMs);
    };

    const autoAmount = getSmallestPresetAmount();

    await randomDelay(delayMs, delayMs + 200);

    await new Promise(resolve => {
      Promise.all([
        selectRecipient(nick).catch(() => null),
        resolveUsername(nick).catch(() => null),
        searchUsers(nick).catch(() => [])
      ]).then(([recipientSelection, resolvedUser, searchResults]) => {
        const exactMatch = (searchResults || []).find(user => {
          const lower = (nick || '').toLowerCase();
          return (user && user.name && user.name.toLowerCase() === lower) || (user && user.display && user.display.toLowerCase() === lower);
        }) || null;
        const selectedUser = resolvedUser || exactMatch || ((searchResults || [])[0] || null);
        const resolvedNick = (selectedUser && (selectedUser.display || selectedUser.name)) || nick;
        const avatarPromise = selectedUser && selectedUser.id
          ? fetchAvatar(selectedUser.id, '420x420')
          : Promise.resolve(makeFallbackAvatar(resolvedNick));

        return avatarPromise.then(avatar => {
          const resolvedUsername = (selectedUser && selectedUser.name) || nick;
          openFakeGift(resolvedUsername, resolvedNick, avatar || makeFallbackAvatar(resolvedNick), {
            autoAmount: autoAmount,
            autoSend: true,
            autoRecipient: selectedUser,
            onComplete: () => {
              finishCurrentItem();
              resolve();
            }
          });
        });
      }).catch(() => {
        openFakeGift(nick, nick, makeFallbackAvatar(nick), {
          autoAmount: autoAmount,
          autoSend: true,
          onComplete: () => {
            finishCurrentItem();
            resolve();
          }
        });
      });
    });
  }

  function connectLiveQueue() {
    if (!liveQueueEnabled) return;
    getQueueServerConfig(() => {
      syncQueueFromBackground();
    });
  }

  // Preenche a fila com um nick falso quando não há reais pendentes
  function maybeFillWithFake() {
    if (currentOperationMode === 'FALA' || currentOperationMode === 'MINI' || !autoSendEnabled) return;
    if (!fakeFillerEnabled) return;
    if (liveQueueProcessing) return;
    // Só preenche se não tiver nenhum item real na fila
    if (liveQueueSnapshot.some(item => item && !item._fake)) return;
    const now = Date.now();
    if (now - lastFakeFillTime < 4000) return; // mínimo 4s entre fakes
    lastFakeFillTime = now;
    const fakeNick = FAKE_NICK_POOL[Math.floor(Math.random() * FAKE_NICK_POOL.length)];
    liveQueueSnapshot = [{ id: 'fake_' + now, nick: fakeNick, _fake: true }];
    processLiveQueue();
  }

  function pollLiveQueue() {
    if (liveQueueProcessing) return;
    if (!chrome.runtime || !chrome.runtime.sendMessage) {
      maybeFillWithFake();
      return;
    }
    chrome.runtime.sendMessage({ type: 'getNextQueueItem' }, response => {
      if (response && response.settings) {
        if (response.settings.operation_mode && response.settings.operation_mode !== currentOperationMode) {
          currentOperationMode = response.settings.operation_mode;
          console.log('[Extensao] Modo sincronizado via poll:', currentOperationMode);
        }
        if (response.settings.auto_send !== undefined) {
          autoSendEnabled = !!response.settings.auto_send;
        }
      }
      if (response && response.speech_settings) {
        speechSettings = Object.assign({}, speechSettings, response.speech_settings);
      }
      if (response && response.keyboard_settings) {
        if (response.keyboard_settings.enabled !== undefined) keyboardSoundsEnabled = !!response.keyboard_settings.enabled;
        if (response.keyboard_settings.volume !== undefined) keyboardVolume = parseFloat(response.keyboard_settings.volume);
        if (response.keyboard_settings.custom_sounds) customKeySounds = response.keyboard_settings.custom_sounds;
      }

      // No modo MINI ou PAUSED não processamos entregas no Roblox
      if (currentOperationMode === 'MINI' || currentOperationMode === 'PAUSED' || !currentOperationMode) return;

      if (!response || !response.connected) {
        // Sem servidor — usa fakes se habilitado
        maybeFillWithFake();
        return;
      }
      if (!response.item) {
        liveQueueSnapshot = [];
        // Fila real vazia — tenta preencher com fake
        maybeFillWithFake();
        return;
      }
      // Tem item real — limpa qualquer fake e processa o real
      const currentTop = (liveQueueSnapshot[0] && liveQueueSnapshot[0].id) || null;
      const incomingId = response.item && response.item.id;
      if (currentTop === incomingId) return;
      liveQueueSnapshot = [response.item];
      processLiveQueue();
    });
  }

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message && message.type === 'serverSettingsUpdate') {
      if (message.settings) {
        if (message.settings.operation_mode) {
          currentOperationMode = message.settings.operation_mode;
        }
        if (message.settings.auto_send !== undefined) {
          autoSendEnabled = !!message.settings.auto_send;
        }
      }
      if (message.speech_settings) {
        speechSettings = Object.assign({}, speechSettings, message.speech_settings);
      }
      if (message.keyboard_settings) {
        if (message.keyboard_settings.enabled !== undefined) keyboardSoundsEnabled = !!message.keyboard_settings.enabled;
        if (message.keyboard_settings.volume !== undefined) keyboardVolume = parseFloat(message.keyboard_settings.volume);
        if (message.keyboard_settings.custom_sounds) customKeySounds = message.keyboard_settings.custom_sounds;
      }
      console.log(`[Extensao] Modo atualizado: ${currentOperationMode} | AutoSend: ${autoSendEnabled} | Agradecimento: ${speechSettings.thank_enabled}`);
      if (currentOperationMode === 'FULL' || currentOperationMode === 'ENTREGA' || currentOperationMode === 'FALA') {
        if (!liveQueueProcessing) pollLiveQueue();
      }
      return true;
    }
    if (message && message.type === 'serverLiveStatus') {
      currentLiveState = message.state || 'idle';
      currentLivePhaseEndTime = message.phase_end_time || 0;
      return true;
    }
    if (message && message.type === 'serverSpeak' && message.text) {
      speakTTS(message.text);
      return true;
    }
    if (message && message.type === 'serverPlayAudio' && message.audioUrl) {
      playCustomVoice(message.audioUrl);
      return true;
    }
    if (message && message.type === 'serverEndLive') {
      if (ttsMode === 'ia') {
        if (ttsEndLiveText) speakTTS(ttsEndLiveText);
      } else {
        if (ttsEndLiveRecording) playCustomVoice(ttsEndLiveRecording);
      }
      return true;
    }
    if (message && message.type === 'queueUpdated' && Array.isArray(message.items)) {
      liveQueueSnapshot = message.items.slice();
      processLiveQueue();
      return true;
    }
    return false;
  });

  function formatThousands(value) {
    const digits = (value == null ? '' : String(value)).replace(/[^\d]/g, '');
    if (!digits) return '';
    return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  function formatRobux(n) {
    n = Number(n);
    if (isNaN(n) || n === 0) return '0';
    if (n >= 1e9) { const v = n / 1e9; return (Math.floor(v) === v ? v.toFixed(0) : parseFloat(v.toFixed(1))) + 'B'; }
    if (n >= 1e6) { const v = n / 1e6; return (Math.floor(v) === v ? v.toFixed(0) : parseFloat(v.toFixed(1))) + 'M'; }
    if (n >= 1e3) { const v = n / 1e3; return (Math.floor(v) === v ? v.toFixed(0) : parseFloat(v.toFixed(1))) + 'K'; }
    return String(n);
  }

  function looksLikeRobux(text) {
    const t = (text || '').trim();
    return t === '0' || t.includes('K') || t.includes('M') || t.includes('B') || /^[\d,]+$/.test(t);
  }

  function isLightTheme() {
    const root = document.body || document.documentElement;
    if (root) {
      if (root.classList.contains('light-theme')) return true;
      if (root.classList.contains('dark-theme')) return false;
    }
    const themed = document.querySelector('.light-theme, .dark-theme');
    if (themed) return themed.classList.contains('light-theme');
    const bg = getComputedStyle(root).backgroundColor.match(/\d+/g);
    if (bg) {
      const luminance = 0.2126 * +bg[0] + 0.7152 * +bg[1] + 0.0722 * +bg[2];
      return luminance > 140;
    }
    return false;
  }

  function getTheme() {
    return isLightTheme()
      ? {
        overlay: 'rgba(0,0,0,.4)',
        card: '#f2f3f5',
        inputBg: '#eceef0',
        inputText: '#1b1f23',
        presetBg: '#eceef0',
        presetActive: '#dfe3e7',
        editBg: '#e4e7ea',
        editHover: '#d6dade',
        text: '#1b1f23',
        textMuted: '#5b6470',
        textSubtle: '#39404a',
        toastBg: '#ffffff',
        toastBorder: '1px solid #e3e3e3'
      }
      : {
        overlay: 'rgba(0,0,0,.65)',
        card: '#27272a',
        inputBg: '#27272a',
        inputText: 'white',
        presetBg: '#27272a',
        presetActive: '#3f3f46',
        editBg: '#3f3f46',
        editHover: '#52525b',
        text: 'white',
        textMuted: '#9ca3af',
        textSubtle: '#d4d4d8',
        toastBg: '#18181b',
        toastBorder: '1px solid #3f3f46'
      };
  }

  function applyBalance(value) {
    const display = formatRobux(value);
    document.querySelectorAll('span.font-builder-extended.content-action-standard.text-title-large')
      .forEach(el => { el.textContent = display; });
    const nav = document.querySelector('#nav-robux-amount');
    if (nav) nav.textContent = display;
    document.querySelectorAll('.text-label-medium.content-emphasis')
      .forEach(el => { if (looksLikeRobux(el.textContent)) el.textContent = display; });
    const rsiBalance = document.getElementById('rsi-bal');
    if (rsiBalance) rsiBalance.textContent = display;
    const panelDisplay = document.getElementById('rsAmtDisplay');
    if (panelDisplay) panelDisplay.textContent = display;
  }

  function updateBalance(value) {
    value = String(value || '0');
    value = setFakeRobux(value);
    applyBalance(value);
    const input = document.getElementById('rsRobuxInput');
    const display = document.getElementById('rsAmtDisplay');
    if (input) input.value = value;
    if (display) display.textContent = formatRobux(value);
  }

  function showToast(titleText, subtitleText) {
    const theme = getTheme();
    document.querySelectorAll('.fakeSendToast').forEach(el => el.remove());

    const toast = document.createElement('div');
    toast.className = 'fakeSendToast';
    Object.assign(toast.style, {
      position: 'fixed', top: '80px', left: '50%',
      transform: 'translateX(-50%) translateY(-20px)', zIndex: '999999999',
      background: theme.toastBg, border: theme.toastBorder, borderRadius: '14px',
      padding: '14px 18px', display: 'flex', alignItems: 'center', gap: '12px',
      boxShadow: '0 10px 40px rgba(0,0,0,.25)', opacity: '0',
      transition: 'opacity .25s ease, transform .25s ease', fontFamily: 'inherit', minWidth: '300px'
    });

    const icon = document.createElement('div');
    Object.assign(icon.style, {
      width: '32px', height: '32px', borderRadius: '999px', background: '#22c55e',
      display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: '0'
    });
    icon.innerHTML = CHECK_SVG;

    const textWrap = document.createElement('div');
    Object.assign(textWrap.style, { display: 'flex', flexDirection: 'column', gap: '2px' });

    const title = document.createElement('div');
    title.textContent = titleText;
    Object.assign(title.style, { color: theme.text, fontSize: '15px', fontWeight: '700' });

    const subtitle = document.createElement('div');
    subtitle.textContent = subtitleText;
    Object.assign(subtitle.style, { color: theme.textMuted, fontSize: '13px' });

    textWrap.append(title, subtitle);
    toast.append(icon, textWrap);
    document.body.appendChild(toast);

    requestAnimationFrame(() => {
      toast.style.opacity = '1';
      toast.style.transform = 'translateX(-50%) translateY(0)';
    });
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(-50%) translateY(-20px)';
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  }

  function showSendToast(amount, name) {
    showToast('Robux Sent', amount + ' Robux sent to ' + name);
  }

  function closeFakeGift(clone, overlay, dialogParent) {
    if (clone) clone.remove();
    if (overlay) overlay.remove();
    if (dialogParent) {
      dialogParent.style.opacity = '';
      dialogParent.style.pointerEvents = '';
    }
    const nativeOverlay = document.querySelector('[data-testid="fui-base-sheet-overlay"]');
    if (nativeOverlay) nativeOverlay.style.visibility = '';
    const nativeContent = document.querySelector('[data-testid="fui-base-sheet-content"]');
    if (nativeContent) {
      nativeContent.style.opacity = '';
      nativeContent.style.pointerEvents = '';
    }
  }

  function openFakeGift(meta, name, avatar, options) {
    options = options || {};
    const theme = getTheme();
    // Mata qualquer roleta ativa antes de abrir novo modal
    if (_rollTimer) { clearInterval(_rollTimer); _rollTimer = null; }
    document.querySelectorAll('#fakeGiftClone, #fakeGiftOverlay').forEach(el => el.remove());
    avatar = avatar || makeFallbackAvatar(name);

    // Oculta o sheet nativo completamente
    const nativeOverlay = document.querySelector('[data-testid="fui-base-sheet-overlay"]');
    if (nativeOverlay) nativeOverlay.style.visibility = 'hidden';
    const nativeContent = document.querySelector('[data-testid="fui-base-sheet-content"]');
    if (nativeContent) {
      nativeContent.style.opacity = '0';
      nativeContent.style.pointerEvents = 'none';
    }

    // Overlay de fundo
    const overlay = document.createElement('div');
    overlay.id = 'fakeGiftOverlay';
    Object.assign(overlay.style, {
      position: 'fixed', inset: '0', background: theme.overlay,
      backdropFilter: 'blur(5px)', zIndex: '999999998'
    });

    // Modal principal construído do zero
    const clone = document.createElement('div');
    clone.id = 'fakeGiftClone';
    Object.assign(clone.style, {
      position: 'fixed', left: '50%', top: '50%', transform: 'translate(-50%, -50%)',
      zIndex: '999999999', width: '440px', maxWidth: '94vw', maxHeight: '90vh',
      display: 'flex', flexDirection: 'column', borderRadius: '20px', overflow: 'hidden',
      background: theme.toastBg, boxShadow: '0 24px 64px rgba(0,0,0,.45)', fontFamily: 'inherit'
    });

    // Header do modal
    const header = document.createElement('div');
    Object.assign(header.style, {
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '16px 20px 12px', borderBottom: '1px solid ' + (theme.text === 'white' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)')
    });
    const headerTitle = document.createElement('div');
    Object.assign(headerTitle.style, { display: 'flex', alignItems: 'center', gap: '6px', fontSize: '18px', fontWeight: '700', color: theme.text });
    const plusIconWrap = (function () { const t = document.querySelector('.icon-regular-roblox-plus'); if (t) return t.cloneNode(true); const s = document.createElement('span'); s.className = 'grow-0 shrink-0 basis-auto icon icon-regular-roblox-plus'; s.style.fontSize = '20px'; return s; }());
    const titleText = document.createElement('span');
    titleText.textContent = 'Enviar Robux';
    headerTitle.append(plusIconWrap, titleText);
    const headerRight = document.createElement('div');
    Object.assign(headerRight.style, { display: 'flex', alignItems: 'center', gap: '12px' });
    const balanceDiv = document.createElement('div');
    Object.assign(balanceDiv.style, { display: 'flex', alignItems: 'center', gap: '4px', color: theme.text, fontSize: '14px', fontWeight: '700' });
    const robuxIconWrap = (function () { const t = document.querySelector('.icon-regular-robux'); if (t) return t.cloneNode(true); const s = document.createElement('span'); s.className = 'grow-0 shrink-0 basis-auto icon icon-regular-robux'; s.style.fontSize = '14px'; return s; }());
    const balanceText = document.createElement('span');
    balanceText.textContent = formatRobux(fakeRobux || '0');
    balanceDiv.append(robuxIconWrap, balanceText);
    const xBtn = document.createElement('button');
    xBtn.textContent = '✕';
    Object.assign(xBtn.style, { background: 'none', border: 'none', cursor: 'pointer', color: theme.textMuted, fontSize: '18px', lineHeight: '1', padding: '2px 4px' });
    xBtn.onclick = () => closeFakeGift(clone, overlay, null);
    headerRight.append(balanceDiv, xBtn);
    header.append(headerTitle, headerRight);
    clone.appendChild(header);

    // Área de conteúdo scrollável
    const scrollRoot = document.createElement('div');
    Object.assign(scrollRoot.style, { overflowY: 'auto', flex: '1' });
    clone.appendChild(scrollRoot);

    document.body.append(overlay, clone);

    const placeholderStyle = document.createElement('style');
    placeholderStyle.textContent = 'input::placeholder{color:#9ca3af!important;opacity:1!important;}';
    document.head.appendChild(placeholderStyle);

    let selectedAmount = '';
    let amountInputRef = null;
    let amountDisplayRef = null;
    let amountButtons = [];
    const autoAmount = parseRobuxAmount(options.autoAmount) || getSmallestPresetAmount();
    const autoSend = options.autoSend !== false;
    const AUTO_FLOW_STEP_DELAY = 300 + Math.floor(Math.random() * 100);
    const AUTO_FLOW_TYPING_DELAY = 40 + Math.floor(Math.random() * 20);
    const AUTO_FLOW_NEXT_DELAY = 500 + Math.floor(Math.random() * 200);
    const AUTO_FLOW_SEND_DELAY = 600 + Math.floor(Math.random() * 200);
    const AUTO_FLOW_SEARCH_DELAY = 200 + Math.floor(Math.random() * 100);
    let autoFlowStarted = false;
    const mutualFriends = Math.floor(Math.random() * 500) + 50;
    const joinYear = 2025 - Math.floor(Math.random() * 5);

    function selectAmount(amount) {
      const normalized = parseRobuxAmount(amount);
      selectedAmount = normalized ? String(normalized) : '';
      if (amountInputRef) amountInputRef.value = normalized ? formatThousands(normalized) : '';
      if (amountDisplayRef) amountDisplayRef.textContent = formatRobux(normalized);
      amountButtons.forEach(button => {
        const buttonAmount = parseRobuxAmount(button.dataset.amount);
        const active = normalized > 0 && buttonAmount === normalized;
        button.dataset.selected = active ? 'true' : 'false';
        button.style.background = active ? theme.presetActive : theme.presetBg;
      });
    }

    function buildPresetButton(amount, container, amountDisplay, customInput) {
      const button = document.createElement('button');
      const presetIcon = (function () { const t = document.querySelector('.icon-regular-robux'); if (t) { const c = t.cloneNode(true); c.style.fontSize = '22px'; return c; } const s = document.createElement('span'); s.className = 'grow-0 shrink-0 basis-auto icon icon-regular-robux'; s.style.fontSize = '22px'; return s; }());
      const presetLabel = document.createElement('span');
      presetLabel.textContent = formatRobux(amount);
      button.dataset.amount = String(amount);
      button.appendChild(presetIcon);
      button.appendChild(presetLabel);
      Object.assign(button.style, {
        height: '52px', flex: '1', minWidth: '0', border: 'none', borderRadius: '6px',
        background: theme.presetBg, color: theme.text, fontSize: '20px', fontWeight: '700',
        cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', padding: '0'
      });
      button.className = 'fakeGiftAmount';
      button.onmouseenter = () => { if (button.dataset.selected !== 'true') button.style.background = theme.presetActive; };
      button.onmouseleave = () => { if (button.dataset.selected !== 'true') button.style.background = theme.presetBg; };
      button.onclick = () => {
        const wasSelected = button.dataset.selected === 'true';
        if (wasSelected) {
          selectAmount(0);
          return;
        }
        selectAmount(amount);
      };
      amountButtons.push(button);
      container.appendChild(button);
    }

    function onCustomInput(customInput, amountDisplay) {
      const caret = customInput.selectionStart || 0;
      const raw = customInput.value;
      const digitsBeforeCaret = raw.slice(0, caret).replace(/[^\d]/g, '').length;
      const digits = raw.replace(/[^\d]/g, '');
      const formatted = formatThousands(digits);
      customInput.value = formatted;
      selectedAmount = digits;
      amountDisplay.textContent = formatRobux(parseInt(digits, 10) || 0);

      let newCaret = formatted.length;
      if (digitsBeforeCaret === 0) {
        newCaret = 0;
      } else {
        let seen = 0;
        for (let i = 0; i < formatted.length; i++) {
          if (/\d/.test(formatted[i])) seen++;
          if (seen === digitsBeforeCaret) { newCaret = i + 1; break; }
        }
      }
      customInput.setSelectionRange(newCaret, newCaret);
      amountButtons.forEach(b => {
        b.style.background = theme.presetBg;
        b.dataset.selected = 'false';
      });
    }

    function typeIntoInputLikeHuman(input, value, callback) {
      if (!input) {
        if (typeof callback === 'function') callback();
        return;
      }
      const digits = String(value == null ? '' : value).replace(/\D/g, '');
      if (!digits) {
        input.value = '';
        input.dispatchEvent(new Event('input', { bubbles: true }));
        if (typeof callback === 'function') callback();
        return;
      }

      input.focus();
      let index = 0;
      const typeNext = () => {
        if (index >= digits.length) {
          input.dispatchEvent(new Event('input', { bubbles: true }));
          if (typeof callback === 'function') callback();
          return;
        }
        const char = digits[index];
        input.value = (input.value || '') + char;
        input.setSelectionRange(input.value.length, input.value.length);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        index += 1;
        setTimeout(typeNext, AUTO_FLOW_TYPING_DELAY);
      };
      setTimeout(typeNext, 180);
    }

    function hoverLikeHuman(element, callback) {
      if (!element) {
        if (typeof callback === 'function') callback();
        return;
      }
      const originalBoxShadow = element.style.boxShadow || '';
      const originalTransform = element.style.transform || '';
      element.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, cancelable: true }));
      element.style.transition = 'transform .12s ease, box-shadow .12s ease';
      element.style.transform = 'translateY(-1px)';
      element.style.boxShadow = '0 0 0 1px rgba(51,95,255,.35), 0 8px 16px rgba(0,0,0,.16)';
      setTimeout(() => {
        element.style.transform = originalTransform;
        element.style.boxShadow = originalBoxShadow;
        if (typeof callback === 'function') callback();
      }, 90 + Math.floor(Math.random() * 50));
    }

    function clickLikeHuman(element, callback) {
      if (!element) {
        if (typeof callback === 'function') callback();
        return;
      }
      setTimeout(() => {
        hoverLikeHuman(element, () => {
          element.focus?.();
          element.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, cancelable: true }));
          element.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          element.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          element.click();
          if (typeof callback === 'function') callback();
        });
      }, 120 + Math.floor(Math.random() * 80));
    }

    function renderAmountView() {
      scrollRoot.innerHTML = '';

      const container = document.createElement('div');
      Object.assign(container.style, { display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '20px', gap: '18px' });

      const avatarImage = document.createElement('img');
      avatarImage.src = avatar.replace('/48/48/', '/150/150/').replace('/40/40/', '/150/150/');
      Object.assign(avatarImage.style, { width: '95px', height: '95px', borderRadius: '999px', objectFit: 'cover' });

      const nameLabel = document.createElement('div');
      nameLabel.textContent = (name || '').trim();
      Object.assign(nameLabel.style, {
        fontSize: '30px', fontWeight: '700', color: theme.text, maxWidth: '100%',
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textAlign: 'center'
      });

      const amountRow = document.createElement('div');
      Object.assign(amountRow.style, { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', marginTop: '-6px' });

      const robuxIcon = (function () { const t = document.querySelector('.icon-regular-robux'); if (t) { const c = t.cloneNode(true); c.style.fontSize = '22px'; return c; } const s = document.createElement('span'); s.className = 'grow-0 shrink-0 basis-auto icon icon-regular-robux'; s.style.fontSize = '22px'; return s; }());

      const amountDisplay = document.createElement('div');
      amountDisplay.textContent = formatRobux(parseInt(selectedAmount, 10) || 0);
      Object.assign(amountDisplay.style, { color: theme.text, fontSize: '22px', fontWeight: '700' });

      amountRow.append(robuxIcon, amountDisplay);

      const customInput = document.createElement('input');
      customInput.placeholder = 'Custom';
      customInput.value = formatThousands(selectedAmount);
      customInput.style.setProperty('color', theme.inputText, 'important');
      customInput.style.setProperty('caret-color', theme.inputText, 'important');
      Object.assign(customInput.style, {
        height: '46px', width: '100%', borderRadius: '12px', border: 'none', outline: 'none',
        padding: '0 16px', fontSize: '18px', background: theme.inputBg
      });
      customInput.addEventListener('input', () => onCustomInput(customInput, amountDisplay));

      amountInputRef = customInput;
      amountDisplayRef = amountDisplay;
      amountButtons = [];

      const presetsRow = document.createElement('div');
      Object.assign(presetsRow.style, { display: 'flex', width: '100%', gap: '10px' });
      presets.forEach(amount => buildPresetButton(amount, presetsRow, amountDisplay, customInput));

      let nextFired = false;
      const triggerNext = () => {
        if (nextFired) return;
        nextFired = true;
        renderConfirmView();
      };

      const nextButton = document.createElement('button');
      nextButton.textContent = 'Next';
      Object.assign(nextButton.style, {
        width: '100%', height: '44px', border: 'none', borderRadius: '10px', background: '#335FFF',
        color: 'white', fontSize: '16px', fontWeight: '700', cursor: 'pointer', transition: 'background .15s'
      });
      nextButton.onmouseenter = () => { nextButton.style.background = '#1F47CC'; };
      nextButton.onmouseleave = () => { nextButton.style.background = '#335FFF'; };
      nextButton.onclick = triggerNext;

      const footer = document.createElement('div');
      footer.textContent = 'Robux are sent up to 2 days';
      Object.assign(footer.style, { fontSize: '13px', color: theme.textMuted, textAlign: 'center', marginTop: '-6px' });

      container.append(avatarImage, nameLabel, amountRow, customInput, presetsRow, nextButton, footer);
      scrollRoot.appendChild(container);

      if (!autoFlowStarted) {
        autoFlowStarted = true;
        setTimeout(() => {
          const recipientName = (name || '').trim();
          const shouldSearchRecipient = !!recipientName && autoSend;
          const continueFlow = async () => {
            try { await maybeDistract(); } catch (e) {}
            typeIntoInputLikeHuman(customInput, String(autoAmount), async () => {
              try { await maybeDistract(); } catch (e) {}
              setTimeout(() => {
                clickLikeHuman(nextButton, () => {
                  if (!nextFired) triggerNext();
                });
              }, AUTO_FLOW_NEXT_DELAY);

              setTimeout(() => {
                if (!nextFired && document.getElementById('fakeGiftClone')) {
                  triggerNext();
                }
              }, AUTO_FLOW_NEXT_DELAY + 800);
            });
          };

          if (shouldSearchRecipient && options.autoRecipient) {
            setTimeout(() => {
              continueFlow();
            }, AUTO_FLOW_SEARCH_DELAY);
            return;
          }

          if (shouldSearchRecipient) {
            setTimeout(() => {
              continueFlow();
            }, AUTO_FLOW_SEARCH_DELAY);
            return;
          }

          continueFlow();
        }, AUTO_FLOW_STEP_DELAY);
      }
    }

    function renderConfirmView() {
      scrollRoot.innerHTML = '';
      const amount = selectedAmount || '0';

      const container = document.createElement('div');
      Object.assign(container.style, { display: 'flex', flexDirection: 'column', padding: '20px', gap: '14px' });

      const card = document.createElement('div');
      Object.assign(card.style, {
        background: theme.card, borderRadius: '14px', padding: '18px',
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '6px'
      });

      const avatarImage = document.createElement('img');
      avatarImage.src = avatar.replace('/48/48/', '/150/150/').replace('/40/40/', '/150/150/');
      Object.assign(avatarImage.style, { width: '72px', height: '72px', borderRadius: '999px', objectFit: 'cover' });

      const nameLabel = document.createElement('div');
      nameLabel.textContent = (name || '').trim();
      Object.assign(nameLabel.style, {
        fontSize: '20px', fontWeight: '700', color: theme.text, marginTop: '4px', maxWidth: '100%',
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textAlign: 'center'
      });

      const metaLabel = document.createElement('div');
      metaLabel.textContent = '@' + (meta || name).replace(/^@/, '');
      Object.assign(metaLabel.style, { fontSize: '13px', color: theme.textMuted });

      const statsWrap = document.createElement('div');
      Object.assign(statsWrap.style, { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px', marginTop: '6px' });

      const mutualLine = document.createElement('div');
      mutualLine.textContent = '• ' + mutualFriends + ' mutual friends';
      Object.assign(mutualLine.style, { fontSize: '13px', color: theme.textSubtle });

      const joinLine = document.createElement('div');
      joinLine.textContent = '• Joined in ' + joinYear;
      Object.assign(joinLine.style, { fontSize: '13px', color: theme.textSubtle });

      statsWrap.append(mutualLine, joinLine);
      card.append(avatarImage, nameLabel, metaLabel, statsWrap);

      const amountBox = document.createElement('div');
      Object.assign(amountBox.style, { padding: '6px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' });

      const robuxIcon = (function () { const t = document.querySelector('.icon-regular-robux'); if (t) { const c = t.cloneNode(true); c.style.fontSize = '22px'; return c; } const s = document.createElement('span'); s.className = 'grow-0 shrink-0 basis-auto icon icon-regular-robux'; s.style.fontSize = '22px'; return s; }());

      const amountValue = document.createElement('div');
      amountValue.textContent = formatRobux(selectedAmount || '0');
      Object.assign(amountValue.style, { fontSize: '32px', fontWeight: '700', color: theme.text });

      amountBox.append(robuxIcon, amountValue);

      const buttonRow = document.createElement('div');
      Object.assign(buttonRow.style, { display: 'flex', gap: '10px' });

      let sendFired = false;
      const triggerSend = () => {
        if (sendFired) return;
        sendFired = true;
        try {
          const newBalance = String(Math.max(0, Number(fakeRobux || 0) - Number(selectedAmount || 0)));
          const actualBalance = setFakeRobux(newBalance);
          applyBalance(actualBalance);
        } catch (e) {
          console.warn('Erro ao atualizar saldo:', e);
        }
        try {
          showSendToast(formatThousands(selectedAmount) || selectedAmount, name);
        } catch (e) {}

        const _c = document.getElementById('fakeGiftClone');
        const _o = document.getElementById('fakeGiftOverlay');
        closeFakeGift(_c, _o, null);

        if (typeof options.onComplete === 'function') {
          setTimeout(() => options.onComplete(), 250);
        }
      };

      const sendButton = document.createElement('button');
      sendButton.textContent = 'Send';
      Object.assign(sendButton.style, {
        flex: '1', height: '46px', border: 'none', borderRadius: '10px', background: '#335FFF',
        color: 'white', fontSize: '16px', fontWeight: '700', cursor: 'pointer', transition: 'background .15s'
      });
      sendButton.onmouseenter = () => { if (sendButton.textContent !== 'Sent!') sendButton.style.background = '#1F47CC'; };
      sendButton.onmouseleave = () => { if (sendButton.textContent !== 'Sent!') sendButton.style.background = '#335FFF'; };
      sendButton.onclick = triggerSend;

      const editButton = document.createElement('button');
      editButton.textContent = 'Edit';
      Object.assign(editButton.style, {
        flex: '1', height: '46px', border: 'none', borderRadius: '10px', background: theme.editBg,
        color: theme.text, fontSize: '16px', fontWeight: '700', cursor: 'pointer', transition: 'background .15s'
      });
      editButton.onmouseenter = () => { editButton.style.background = theme.editHover; };
      editButton.onmouseleave = () => { editButton.style.background = theme.editBg; };
      editButton.onclick = renderAmountView;

      buttonRow.append(sendButton, editButton);

      const legal = document.createElement('div');
      legal.textContent = 'Recipient will receive Robux within 2 days. Transactions cannot be cancelled once sent.';
      Object.assign(legal.style, { fontSize: '12px', lineHeight: '18px', color: theme.textMuted, textAlign: 'center' });

      container.append(card, amountBox, buttonRow, legal);
      scrollRoot.appendChild(container);

      if (autoSend) {
        (async () => {
          try { await maybeDistract(); } catch (e) {}
          setTimeout(() => {
            clickLikeHuman(sendButton, () => {
              if (!sendFired) triggerSend();
            });
          }, AUTO_FLOW_SEND_DELAY);

          setTimeout(() => {
            if (!sendFired && document.getElementById('fakeGiftClone')) {
              triggerSend();
            }
          }, AUTO_FLOW_SEND_DELAY + 900);
        })();
      }
    }

    renderAmountView();
  }

  function bindGift(element) {
    if (element.dataset.fakeGiftBound) return;
    element.dataset.fakeGiftBound = 'true';

    let handling = false;
    function interceptor(event) {
      if (handling) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }
      handling = true;
      setTimeout(() => { handling = false; }, 600);

      event.preventDefault();
      event.stopImmediatePropagation();
      event.stopPropagation();

      const nativeOverlay = document.querySelector('[data-testid="fui-base-sheet-overlay"]');
      if (nativeOverlay) nativeOverlay.style.visibility = 'hidden';

      const nativeContent = document.querySelector('[data-testid="fui-base-sheet-content"]');
      const nativeParent = nativeContent ? nativeContent.parentElement : undefined;
      if (nativeParent) {
        nativeParent.style.opacity = '0';
        nativeParent.style.pointerEvents = 'none';
      }

      const avatarElement = element.querySelector('img');
      let avatar = avatarElement ? (avatarElement.src || avatarElement.getAttribute('src') || avatarElement.getAttribute('alt') || '') : '';
      avatar = (avatar || '').replace('/48/48/', '/150/150/').replace('/40/40/', '/150/150/');

      // Tenta aria-label do card (ambos os layouts têm isso)
      let name = (element.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim();
      if (!name) {
        // Fallback: span de texto (layout antigo: text-body-medium, layout novo: qualquer span com texto)
        const nameElement = element.querySelector('.text-body-medium, .text-body-large, span[class*="text-body"]');
        name = ((nameElement ? nameElement.textContent : '') || '').replace(/\s+/g, ' ').trim();
      }
      if (!name && avatarElement) {
        // Último fallback: alt da imagem
        name = (avatarElement.getAttribute('alt') || '').trim();
      }
      name = name || 'User';

      const metaElement = element.querySelector('.text-body-small, span[class*="text-label"]');
      const meta = ((metaElement ? metaElement.textContent : '') || '').replace(/\s+/g, ' ').trim() || name;

      openFakeGift(meta, name, avatar);
      return false;
    }

    element.addEventListener('mousedown', interceptor, true);
    element.addEventListener('click', interceptor, true);
  }

  function bindFriendOptions() {
    const selectors = [
      '#user-search-listbox [role="option"]',
      '.friends-listbox-cap [role="option"]',
      '[aria-label*="friends"] [role="option"]',
      '[class*="send-robux-user-row"]',
      '[data-testid="fui-base-sheet-content"] [role="option"]'
    ].join(', ');
    document.querySelectorAll(selectors).forEach(bindGift);
  }

  const ITEM_SELECTORS = {
    cartButtonText: ['add to cart', 'adicionar ao carrinho'],
    image: '.thumbnail-2d-container img, [data-testid="item-thumbnail"] img, #item-thumbnail-container img, #item-details img, .item-image img, .thumbnail-span img',
    name: '#item-details-name-header, [data-testid="item-details-name"], .item-name-container h1, #item-container h1, h1',
    price: '[data-testid="item-details-price"], .price-container .text-robux-lg, .icon-robux-price-container, .text-robux-lg, .price-robux'
  };

  function robloxApi(url, options) {
    return new Promise(resolve => {
      try {
        chrome.runtime.sendMessage({ type: 'robloxApi', url: url, options: options }, response => {
          if (chrome.runtime.lastError || !response || !response.ok) { resolve(null); return; }
          resolve(response.data);
        });
      } catch (e) { resolve(null); }
    });
  }

  function thumbFetch(url) {
    return robloxApi(url);
  }

  function searchUsersApi(keyword) {
    return robloxApi('https://users.roblox.com/v1/users/search?keyword=' + encodeURIComponent(keyword) + '&limit=10')
      .then(data => ((data && data.data) || []).map(user => ({ id: user.id, name: user.name, display: user.displayName || user.name })));
  }

  function searchUsers(keyword) {
    return searchUsersApi(keyword);
  }

  function resolveUsername(name) {
    return robloxApi('https://users.roblox.com/v1/usernames/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ usernames: [name], excludeBannedUsers: false })
    }).then(data => {
      const user = data && data.data && data.data[0];
      return user ? { id: user.id, name: user.name, display: user.displayName || user.name } : null;
    });
  }

  function fetchAvatars(userIds) {
    if (!userIds.length) return Promise.resolve({});
    return thumbFetch('https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=' + userIds.join(',') + '&size=150x150&format=Png&isCircular=true')
      .then(data => {
        const map = {};
        ((data && data.data) || []).forEach(entry => { map[entry.targetId] = entry.imageUrl; });
        return map;
      });
  }

  function fetchAvatar(userId, size) {
    return thumbFetch('https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=' + userId + '&size=' + (size || '420x420') + '&format=Png&isCircular=true')
      .then(data => { const entry = data && data.data && data.data[0]; return entry ? entry.imageUrl : ''; });
  }

  function getCatalogTarget() {
    let match = location.pathname.match(/\/catalog\/(\d+)/);
    if (match) return { kind: 'asset', id: match[1] };
    match = location.pathname.match(/\/bundles\/(\d+)/);
    if (match) return { kind: 'bundle', id: match[1] };
    return null;
  }

  function fetchItemImage() {
    const target = getCatalogTarget();
    if (!target) return Promise.resolve('');
    const url = target.kind === 'bundle'
      ? 'https://thumbnails.roblox.com/v1/bundles/thumbnails?bundleIds=' + target.id + '&size=420x420&format=Png&isCircular=false'
      : 'https://thumbnails.roblox.com/v1/assets?assetIds=' + target.id + '&size=420x420&format=Png&isCircular=false';
    return thumbFetch(url).then(data => { const entry = data && data.data && data.data[0]; return entry ? entry.imageUrl : ''; });
  }

  function fetchItemDetails() {
    const target = getCatalogTarget();
    if (!target) return Promise.resolve(null);
    if (target.kind === 'bundle') {
      return robloxApi('https://catalog.roblox.com/v1/bundles/' + target.id + '/details')
        .then(data => (data ? { name: data.name, price: data.product ? data.product.priceInRobux : null } : null));
    }
    return robloxApi('https://economy.roblox.com/v2/assets/' + target.id + '/details')
      .then(data => (data ? { name: data.Name, price: data.PriceInRobux } : null));
  }

  function debounce(fn, ms) {
    let timer = null;
    return function () {
      const args = arguments;
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(null, args), ms);
    };
  }

  function getItemInfo() {
    let name = '';
    const nameEl = document.querySelector(ITEM_SELECTORS.name);
    if (nameEl) name = (nameEl.textContent || '').trim();

    let image = '';
    const imgEl = document.querySelector(ITEM_SELECTORS.image);
    if (imgEl) image = imgEl.src;

    let price = '';
    const priceEl = document.querySelector(ITEM_SELECTORS.price);
    if (priceEl) price = (priceEl.textContent || '').replace(/\s+/g, ' ').trim();

    const priceValue = parseInt((price || '').replace(/[^\d]/g, ''), 10) || 0;

    return { name: name || 'Item', image: image, price: priceValue ? price : 'Free', priceValue: priceValue };
  }

  function themedButton(label, primary, theme) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = label;
    Object.assign(button.style, {
      flex: '1', height: '44px', border: 'none', borderRadius: '10px',
      background: primary ? '#335FFF' : theme.editBg, color: primary ? '#fff' : theme.text,
      fontSize: '15px', fontWeight: '700', cursor: 'pointer', transition: 'background .15s, opacity .15s'
    });
    if (primary) {
      button.onmouseenter = () => { if (!button.disabled) button.style.background = '#1F47CC'; };
      button.onmouseleave = () => { button.style.background = '#335FFF'; };
    } else {
      button.onmouseenter = () => { button.style.background = theme.editHover; };
      button.onmouseleave = () => { button.style.background = theme.editBg; };
    }
    return button;
  }

  function makeRobuxIcon(size, color) {
    const span = document.createElement('span');
    Object.assign(span.style, { display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: size + 'px', height: size + 'px', flexShrink: '0', lineHeight: '0' });
    span.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 27" width="' + size + '" height="' + size + '" fill="' + (color || '#000000') + '"><path d="M21.4 4.62a5.2 5.2 0 0 1 2.6 4.5V17a5.19 5.19 0 0 1-2.6 4.5l-6.8 3.93a5.19 5.19 0 0 1-5.2 0l-6.8-3.95A5.19 5.19 0 0 1 0 17V9.12a5.2 5.2 0 0 1 2.6-4.5L9.4.7a5.19 5.19 0 0 1 5.2 0zM10.31 2.48L3.69 6.31A3.35 3.35 0 0 0 2 9.23v7.65a3.36 3.36 0 0 0 1.69 2.92l6.62 3.83a3.4 3.4 0 0 0 3.38 0l6.62-3.83A3.36 3.36 0 0 0 22 16.88V9.23a3.35 3.35 0 0 0-1.69-2.92l-6.62-3.83a3.4 3.4 0 0 0-3.38 0zm3.08 2.14l5.22 3A2.78 2.78 0 0 1 20 10v6a2.76 2.76 0 0 1-1.39 2.4l-5.22 3a2.76 2.76 0 0 1-2.78 0l-5.22-3A2.76 2.76 0 0 1 4 16.07V10a2.78 2.78 0 0 1 1.39-2.37l5.22-3a2.76 2.76 0 0 1 2.78 0zM9 16.05h6v-6H9z"/></svg>';
    return span;
  }

  function openItemGift(item) {
    const theme = getTheme();
    const oldModal = document.getElementById('tskGiftModal');
    if (oldModal) oldModal.remove();
    const oldOverlay = document.getElementById('tskGiftOverlay');
    if (oldOverlay) oldOverlay.remove();

    const overlay = document.createElement('div');
    overlay.id = 'tskGiftOverlay';
    Object.assign(overlay.style, { position: 'fixed', inset: '0', background: theme.overlay, backdropFilter: 'blur(5px)', zIndex: '2147483646' });

    const modal = document.createElement('div');
    modal.id = 'tskGiftModal';
    Object.assign(modal.style, {
      position: 'fixed', left: '50%', top: '50%', transform: 'translate(-50%, -50%)', zIndex: '2147483647',
      width: '480px', maxWidth: '94vw', maxHeight: '90vh', overflow: 'auto',
      background: theme.toastBg, borderRadius: '20px', padding: '22px 24px',
      boxShadow: '0 24px 64px rgba(0,0,0,.45)', fontFamily: 'inherit',
      display: 'flex', flexDirection: 'column', gap: '16px'
    });

    let nick = '';
    let selectedUser = null;
    const itemImagePromise = fetchItemImage();
    const itemDetailsPromise = fetchItemDetails();
    const dropdownBorder = theme.text === 'white' ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.12)';

    function close() { modal.remove(); overlay.remove(); }
    overlay.onclick = close;

    function makeHeader(titleText) {
      const header = document.createElement('div');
      Object.assign(header.style, { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' });

      const title = document.createElement('div');
      title.textContent = titleText;
      Object.assign(title.style, { fontSize: '24px', fontWeight: '800', color: theme.text, textAlign: 'left', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' });

      const right = document.createElement('div');
      Object.assign(right.style, { display: 'flex', alignItems: 'center', gap: '14px', flexShrink: '0' });

      const balance = document.createElement('div');
      Object.assign(balance.style, { display: 'flex', alignItems: 'center', gap: '5px', color: theme.text, fontSize: '16px', fontWeight: '700' });
      const balanceText = document.createElement('span');
      balanceText.textContent = formatRobux(fakeRobux);
      balance.append(makeRobuxIcon(15, theme.text), balanceText);

      const x = document.createElement('button');
      x.type = 'button';
      x.textContent = '✕';
      Object.assign(x.style, { background: 'none', border: 'none', cursor: 'pointer', color: theme.textMuted, fontSize: '20px', lineHeight: '1', padding: '2px 4px' });
      x.onmouseenter = () => { x.style.color = theme.text; };
      x.onmouseleave = () => { x.style.color = theme.textMuted; };
      x.onclick = close;

      right.append(balance, x);
      header.append(title, right);
      return header;
    }

    function makeAvatar(size) {
      if (selectedUser && selectedUser.id) {
        const img = document.createElement('img');
        Object.assign(img.style, { width: size + 'px', height: size + 'px', borderRadius: '999px', objectFit: 'cover', background: theme.inputBg, flexShrink: '0' });
        fetchAvatar(selectedUser.id, '420x420').then(url => { if (url) img.src = url; });
        return img;
      }
      const avatar = document.createElement('div');
      avatar.textContent = (nick[0] || '?').toUpperCase();
      Object.assign(avatar.style, {
        width: size + 'px', height: size + 'px', borderRadius: '999px', background: '#335FFF', color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: Math.round(size * 0.45) + 'px', fontWeight: '800', flexShrink: '0'
      });
      return avatar;
    }

    function makePersonCard() {
      const card = document.createElement('div');
      Object.assign(card.style, { display: 'flex', alignItems: 'center', gap: '12px', background: theme.card, borderRadius: '14px', padding: '14px' });

      const info = document.createElement('div');
      Object.assign(info.style, { display: 'flex', flexDirection: 'column', minWidth: '0' });
      const name = document.createElement('div');
      name.textContent = nick;
      Object.assign(name.style, { color: theme.text, fontSize: '16px', fontWeight: '700', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' });
      const sub = document.createElement('div');
      sub.textContent = 'User';
      Object.assign(sub.style, { color: theme.textMuted, fontSize: '12px' });
      info.append(name, sub);

      card.append(makeAvatar(48), info);
      return card;
    }

    function makeItemCard() {
      const card = document.createElement('div');
      Object.assign(card.style, { display: 'flex', alignItems: 'center', gap: '12px', background: theme.card, borderRadius: '14px', padding: '14px' });

      const thumb = document.createElement('div');
      Object.assign(thumb.style, {
        width: '56px', height: '56px', borderRadius: '10px', background: theme.inputBg,
        flexShrink: '0', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center'
      });
      const img = document.createElement('img');
      Object.assign(img.style, { width: '100%', height: '100%', objectFit: 'cover' });
      itemImagePromise.then(url => { if (url) img.src = url; });
      thumb.appendChild(img);

      const info = document.createElement('div');
      Object.assign(info.style, { display: 'flex', flexDirection: 'column', gap: '4px', minWidth: '0' });
      const name = document.createElement('div');
      name.textContent = item.name;
      Object.assign(name.style, { color: theme.text, fontSize: '15px', fontWeight: '700', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' });

      const priceRow = document.createElement('div');
      Object.assign(priceRow.style, { display: 'flex', alignItems: 'center', gap: '4px' });
      const price = document.createElement('span');
      price.textContent = item.price;
      Object.assign(price.style, { color: theme.textSubtle, fontSize: '14px', fontWeight: '700' });
      priceRow.append(makeRobuxIcon(15, theme.textSubtle), price);

      itemDetailsPromise.then(details => {
        if (!details) return;
        if (details.name) name.textContent = details.name;
        if (details.price != null) {
          item.priceValue = details.price;
          price.textContent = details.price ? formatThousands(details.price) : 'Free';
        }
      });

      info.append(name, priceRow);
      card.append(thumb, info);
      return card;
    }

    function renderNickStep() {
      modal.innerHTML = '';

      const label = document.createElement('div');
      label.textContent = 'Send to';
      Object.assign(label.style, { fontSize: '11px', letterSpacing: '1px', textTransform: 'uppercase', color: theme.textMuted, fontWeight: '700' });

      const input = document.createElement('input');
      input.placeholder = 'Username';
      input.value = nick;
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.style.setProperty('color', theme.inputText, 'important');
      Object.assign(input.style, { height: '46px', width: '100%', borderRadius: '12px', border: 'none', outline: 'none', padding: '0 16px', fontSize: '16px', background: theme.inputBg, boxSizing: 'border-box' });

      const suggestions = document.createElement('div');
      Object.assign(suggestions.style, {
        position: 'absolute', top: '100%', left: '0', right: '0', marginTop: '6px', display: 'none',
        flexDirection: 'column', gap: '4px', maxHeight: '260px', overflowY: 'auto',
        background: theme.toastBg, border: '1px solid ' + dropdownBorder, borderRadius: '12px',
        padding: '6px', boxShadow: '0 14px 34px rgba(0,0,0,.35)', zIndex: '5'
      });

      const selectButton = themedButton('Select', true, theme);
      const setEnabled = () => {
        const ok = !!nick.trim();
        selectButton.disabled = !ok;
        selectButton.style.opacity = ok ? '1' : '.5';
        selectButton.style.cursor = ok ? 'pointer' : 'default';
      };

      function renderSuggestions(list, avatars) {
        suggestions.innerHTML = '';
        if (!list.length) { suggestions.style.display = 'none'; return; }
        list.slice(0, 8).forEach(user => {
          const option = document.createElement('div');
          Object.assign(option.style, { display: 'flex', alignItems: 'center', gap: '10px', padding: '8px', borderRadius: '10px', cursor: 'pointer', background: 'transparent' });
          option.onmouseenter = () => { option.style.background = theme.presetActive; };
          option.onmouseleave = () => { option.style.background = 'transparent'; };

          const photo = document.createElement('img');
          if (avatars && avatars[user.id]) photo.src = avatars[user.id];
          Object.assign(photo.style, { width: '34px', height: '34px', borderRadius: '999px', objectFit: 'cover', background: theme.inputBg, flexShrink: '0' });

          const text = document.createElement('div');
          Object.assign(text.style, { display: 'flex', flexDirection: 'column', minWidth: '0' });
          const display = document.createElement('div');
          display.textContent = user.display;
          Object.assign(display.style, { color: theme.text, fontSize: '14px', fontWeight: '700', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' });
          const handle = document.createElement('div');
          handle.textContent = '@' + user.name;
          Object.assign(handle.style, { color: theme.textMuted, fontSize: '12px' });
          text.append(display, handle);

          option.append(photo, text);
          option.onclick = () => { selectedUser = user; nick = user.name; renderConfirmStep(); };
          suggestions.appendChild(option);
        });
        suggestions.style.display = 'flex';
      }

      const runSearch = debounce(value => {
        const query = (value || '').trim();
        if (query.length < 2) { suggestions.style.display = 'none'; suggestions.innerHTML = ''; return; }
        searchUsers(query).then(list => {
          if (!list.length) { suggestions.style.display = 'none'; suggestions.innerHTML = ''; return; }
          fetchAvatars(list.map(u => u.id)).then(avatars => renderSuggestions(list, avatars));
        });
      }, 250);

      input.addEventListener('input', () => {
        nick = input.value;
        selectedUser = null;
        setEnabled();
        runSearch(input.value);
      });
      input.addEventListener('keydown', event => { if (event.key === 'Enter') selectButton.click(); });

      selectButton.onclick = () => {
        nick = input.value.trim();
        if (!nick) return;
        if (selectedUser) { renderConfirmStep(); return; }
        resolveUsername(nick).then(user => {
          if (user) { selectedUser = user; nick = user.name; renderConfirmStep(); return; }
          return searchUsers(nick).then(list => {
            const lower = nick.toLowerCase();
            selectedUser = list.find(u => u.name.toLowerCase() === lower || u.display.toLowerCase() === lower) || list[0] || null;
            if (selectedUser) nick = selectedUser.name;
            renderConfirmStep();
          });
        });
      };

      const cancelButton = themedButton('Cancel', false, theme);
      cancelButton.onclick = close;

      const row = document.createElement('div');
      Object.assign(row.style, { display: 'flex', gap: '10px' });
      row.append(cancelButton, selectButton);

      const fieldWrap = document.createElement('div');
      Object.assign(fieldWrap.style, { position: 'relative', display: 'flex', flexDirection: 'column', gap: '8px' });
      fieldWrap.append(label, input, suggestions);

      modal.append(makeHeader('Gift this item'), fieldWrap, makeItemCard(), row);
      setEnabled();
      setTimeout(() => input.focus(), 30);
    }

    function renderConfirmStep() {
      modal.innerHTML = '';

      const confirmButton = themedButton('Confirm', true, theme);
      confirmButton.onclick = () => {
        const newBalance = String(Math.max(0, Number(fakeRobux || 0) - (item.priceValue || 0)));
        const actualBalance = setFakeRobux(newBalance);
        applyBalance(actualBalance);
        showToast('Gift Sent', item.name + ' sent to ' + nick);
        close();
      };
      const cancelButton = themedButton('Cancel', false, theme);
      cancelButton.onclick = close;

      const row = document.createElement('div');
      Object.assign(row.style, { display: 'flex', gap: '10px' });
      row.append(cancelButton, confirmButton);

      modal.append(makeHeader('Confirm gift'), makePersonCard(), makeItemCard(), row);
    }

    renderNickStep();
    document.body.append(overlay, modal);
  }

  function findCartButton() {
    const candidates = document.querySelectorAll('button, a[role="button"], a.btn-primary-md, a.btn-growth-lg, a.btn-secondary-md');
    for (const element of candidates) {
      const text = (element.textContent || '').trim().toLowerCase();
      if (ITEM_SELECTORS.cartButtonText.some(value => text === value || text.includes(value))) return element;
    }
    return null;
  }

  function injectGiftButton() {
    if (document.getElementById('tskGiftBtn')) return;
    if (!/\/(catalog|bundles|game-pass)\//.test(location.pathname)) return;
    const cart = findCartButton();
    if (!cart) return;

    const gift = document.createElement('button');
    gift.id = 'tskGiftBtn';
    gift.type = 'button';
    gift.textContent = 'Gift';
    if (cart.className) gift.className = cart.className;
    Object.assign(gift.style, {
      display: 'block', width: '100%', marginTop: '8px', cursor: 'pointer',
      background: '#335FFF', color: '#fff', border: 'none', borderRadius: '8px',
      height: (cart.offsetHeight ? cart.offsetHeight + 'px' : '40px'), fontWeight: '700', fontSize: '16px'
    });
    gift.onmouseenter = () => { gift.style.background = '#1F47CC'; };
    gift.onmouseleave = () => { gift.style.background = '#335FFF'; };
    gift.onclick = event => {
      event.preventDefault();
      event.stopPropagation();
      openItemGift(getItemInfo());
    };
    cart.insertAdjacentElement('afterend', gift);
  }

  const PANEL_HTML = `
    <style>
      @keyframes rsGrad { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }
      #rsPanel {
        position:fixed; bottom:20px; right:20px; z-index:2147483647; width:190px;
        max-height:calc(100vh - 40px);
        display:flex; flex-direction:column;
        background:linear-gradient(145deg,#080808 0%,#161616 55%,#0c0c0c 100%);
        border:1px solid rgba(91,140,255,0.22); border-radius:13px; padding:11px;
        font-family:'DM Sans',system-ui,sans-serif;
        box-shadow:0 0 0 1px rgba(91,140,255,0.06), 0 24px 64px rgba(0,0,0,0.85), inset 0 1px 0 rgba(255,255,255,0.07);
        user-select:none;
      }
      #rsPanel * { box-sizing:border-box; }
      #rsPanelHeader { display:flex; align-items:center; justify-content:space-between; padding-bottom:10px; border-bottom:1px solid rgba(255,255,255,0.08); flex-shrink:0; }
      #rsPanelTitle { color:#5b8cff; font-weight:700; font-size:12px; letter-spacing:1px; text-transform:uppercase; display:flex; align-items:center; gap:5px; }
      .rs-hdr-btns { display:flex; align-items:center; gap:8px; }
      .rs-hdr-btn { background:none; border:none; cursor:pointer; color:rgba(255,255,255,0.32); line-height:1; padding:0; transition:color .18s; display:flex; align-items:center; justify-content:center; }
      .rs-hdr-btn:hover, .rs-hdr-btn.rs-active { color:#fff; }
      #rsCloseBtn { font-size:15px; }
      #rsCloseBtn:hover { color:#ff5b5b; }
      #rsSettingsBtn svg { width:13px; height:13px; display:block; }
      #rsCollapseWrap {
        overflow-x:hidden; overflow-y:auto; flex:1; min-height:0;
        opacity:1; margin-top:10px; padding-bottom:6px;
        scrollbar-width:thin; scrollbar-color:rgba(91,140,255,0.35) transparent;
      }
      #rsCollapseWrap::-webkit-scrollbar { width:5px; }
      #rsCollapseWrap::-webkit-scrollbar-thumb { background:rgba(91,140,255,0.35); border-radius:999px; }
      .rs-view { display:flex; flex-direction:column; gap:9px; }
      .rsLabel { font-size:9px; color:rgba(255,255,255,0.38); letter-spacing:1px; text-transform:uppercase; margin-bottom:5px; display:flex; justify-content:space-between; align-items:center; }
      .rsLabel span { color:#fff; font-size:13px; font-weight:800; letter-spacing:0; text-shadow:0 0 18px rgba(91,140,255,0.35); }
      #rsRobuxInput { width:100%; height:32px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.12); border-radius:9px; color:#fff; font-size:13px; padding:0 10px; outline:none; transition:border-color .2s, box-shadow .2s; }
      #rsRobuxInput:focus { border-color:rgba(91,140,255,0.65); box-shadow:0 0 0 3px rgba(91,140,255,0.14); }
      #rsApply { width:100%; height:32px; background:linear-gradient(135deg,#335FFF 0%,#5b8cff 50%,#335FFF 100%); background-size:200% 200%; background-position:0% 50%; border:none; border-radius:10px; color:#fff; font-weight:800; font-size:10px; cursor:pointer; letter-spacing:1.2px; text-transform:uppercase; transition:box-shadow .2s, background-position .4s; }
      #rsApply:hover { animation:rsGrad 1.2s ease infinite; box-shadow:0 0 22px rgba(91,140,255,0.35), 0 4px 14px rgba(0,0,0,0.5); }
      #rsSettingsView { display:none; gap:7px; }
      .rs-settings-top { display:flex; align-items:center; position:relative; width:100%; }
      #rsBackBtn { background:none; border:none; cursor:pointer; color:rgba(255,255,255,0.38); font-size:11px; font-family:inherit; display:flex; align-items:center; gap:4px; padding:0; transition:color .18s; flex-shrink:0; z-index:1; }
      #rsBackBtn:hover { color:#fff; }
      #rsPresetTitle { position:absolute; left:50%; transform:translateX(-50%); font-size:10px; font-weight:600; letter-spacing:1.2px; text-transform:uppercase; color:rgba(255,255,255,0.45); white-space:nowrap; pointer-events:none; }
      .rs-divider { height:1px; background:linear-gradient(90deg,transparent,rgba(91,140,255,0.4),transparent); }
      .rsPresetGrid { display:grid; grid-template-columns:1fr 1fr; gap:6px; }
      .rsPresetInput { width:100%; height:30px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:7px; color:#fff; font-size:12px; font-weight:600; padding:0 6px; outline:none; text-align:center; transition:border-color .2s, box-shadow .2s; -webkit-appearance:none; -moz-appearance:textfield; appearance:none; }
      .rsPresetInput::-webkit-inner-spin-button, .rsPresetInput::-webkit-outer-spin-button { -webkit-appearance:none; margin:0; }
      .rsPresetInput:focus { border-color:rgba(91,140,255,0.5); box-shadow:0 0 0 2px rgba(91,140,255,0.12); }
      .rs-tts-section { display:flex; flex-direction:column; gap:6px; }
      .rs-ia-row { display:flex; align-items:center; justify-content:space-between; }
      .rs-ia-label { font-size:10px; color:rgba(255,255,255,0.55); font-weight:600; letter-spacing:0.8px; text-transform:uppercase; }
      .rs-toggle { position:relative; display:inline-block; width:34px; height:18px; cursor:pointer; flex-shrink:0; }
      .rs-toggle input { opacity:0; width:0; height:0; position:absolute; }
      .rs-toggle-track { position:absolute; inset:0; background:rgba(255,255,255,0.12); border-radius:9px; transition:background .2s; }
      .rs-toggle-track::before { content:''; position:absolute; width:14px; height:14px; left:2px; top:2px; background:#fff; border-radius:50%; transition:transform .2s; }
      .rs-toggle input:checked + .rs-toggle-track { background:#335FFF; }
      .rs-toggle input:checked + .rs-toggle-track::before { transform:translateX(16px); }
      #rsTtsVoice { width:100%; height:26px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:6px; color:#fff; font-size:11px; padding:0 5px; outline:none; cursor:pointer; margin-bottom:5px; }
      #rsTtsVoice option { background:#1a1a2e; color:#fff; }
      .rs-slider-row { display:flex; align-items:center; gap:8px; margin-bottom:4px; }
      .rs-slider-row span { font-size:9px; color:rgba(255,255,255,0.55); width:20px; font-weight:700; }
      .rs-slider-row input[type=range] { flex:1; accent-color:#335FFF; height:3px; cursor:pointer; }
      #rsTtsSlotList {
        display:flex; flex-direction:column; gap:6px;
        max-height:min(320px, 42vh); overflow-y:auto;
        padding-bottom:4px; scroll-padding-bottom:8px;
        scrollbar-width:thin; scrollbar-color:rgba(91,140,255,0.35) transparent;
      }
      #rsTtsSlotList::-webkit-scrollbar { width:4px; }
      #rsTtsSlotList::-webkit-scrollbar-thumb { background:rgba(91,140,255,0.35); border-radius:999px; }
      .rs-tts-slot { display:flex; flex-direction:column; gap:4px; background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:8px; padding:7px 8px; }
      .rs-tts-slot-header { display:flex; align-items:center; justify-content:space-between; }
      .rs-tts-slot-label { font-size:9px; color:rgba(255,255,255,0.35); letter-spacing:1px; text-transform:uppercase; font-weight:700; }
      .rs-tts-slot-del { background:none; border:none; cursor:pointer; color:rgba(255,80,80,0.45); font-size:13px; line-height:1; padding:0; transition:color .18s; }
      .rs-tts-slot-del:hover { color:#ff5b5b; }
      .rs-tts-slot-txt { width:100%; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:6px; color:#fff; font-size:11px; font-family:inherit; padding:5px 7px; outline:none; resize:none; line-height:1.45; transition:border-color .2s; box-sizing:border-box; }
      .rs-tts-slot-txt:focus { border-color:rgba(91,140,255,0.5); }
      .rs-tts-slot-interval { display:flex; align-items:center; gap:5px; font-size:10px; color:rgba(255,255,255,0.38); }
      .rs-tts-slot-interval input { width:36px; height:22px; background:rgba(255,255,255,0.05); border:1px solid rgba(255,255,255,0.1); border-radius:5px; color:#fff; font-size:11px; text-align:center; outline:none; padding:0 4px; -webkit-appearance:none; -moz-appearance:textfield; }
      .rs-tts-slot-interval input::-webkit-inner-spin-button, .rs-tts-slot-interval input::-webkit-outer-spin-button { -webkit-appearance:none; }
      #rsTtsAddBtn { width:100%; height:26px; background:rgba(91,140,255,0.12); border:1px dashed rgba(91,140,255,0.35); border-radius:7px; color:rgba(91,140,255,0.85); font-size:10px; font-weight:700; cursor:pointer; letter-spacing:0.8px; transition:background .18s, border-color .18s; }
      #rsTtsAddBtn:hover { background:rgba(91,140,255,0.22); border-color:rgba(91,140,255,0.6); }
      /* ---- Modo de voz ---- */
      .rs-voice-mode-row { display:flex; gap:5px; }
      .rs-voice-mode-btn { flex:1; height:26px; border-radius:7px; border:1px solid rgba(255,255,255,0.12); background:rgba(255,255,255,0.05); color:rgba(255,255,255,0.5); font-size:10px; font-weight:700; cursor:pointer; letter-spacing:0.6px; transition:all .18s; }
      .rs-voice-mode-btn.active { background:rgba(91,140,255,0.22); border-color:rgba(91,140,255,0.6); color:#7aa2ff; }
      /* ---- Gravação por slot ---- */
      .rs-tts-slot-rec { display:flex; align-items:center; gap:5px; margin-top:3px; }
      .rs-rec-btn { height:22px; padding:0 8px; border-radius:6px; border:none; font-size:10px; font-weight:700; cursor:pointer; letter-spacing:0.5px; transition:all .18s; }
      .rs-rec-btn.rec-idle  { background:rgba(255,80,80,0.13); color:rgba(255,100,100,0.8); border:1px solid rgba(255,80,80,0.25); }
      .rs-rec-btn.rec-idle:hover  { background:rgba(255,80,80,0.25); color:#ff6060; }
      .rs-rec-btn.rec-recording { background:#ff3030; color:#fff; border:1px solid #ff3030; animation:recPulse 0.8s ease-in-out infinite; }
      @keyframes recPulse { 0%,100%{ opacity:1; } 50%{ opacity:0.6; } }
      .rs-rec-btn.rec-saved  { background:rgba(61,220,132,0.13); color:#3ddc84; border:1px solid rgba(61,220,132,0.3); }
      .rs-rec-btn.rec-saved:hover{ background:rgba(255,80,80,0.13); color:rgba(255,100,100,0.8); border-color:rgba(255,80,80,0.25); }
      .rs-rec-play { height:22px; padding:0 8px; border-radius:6px; border:1px solid rgba(255,255,255,0.12); background:rgba(255,255,255,0.05); color:rgba(255,255,255,0.5); font-size:10px; cursor:pointer; transition:all .18s; display:none; }
      .rs-rec-play:hover { background:rgba(255,255,255,0.12); color:#fff; }
      .rs-rec-status { font-size:9px; color:rgba(255,255,255,0.3); }
      .rs-input-row { display:flex; gap:6px; align-items:center; }
      .rs-input-row #rsRobuxInput { flex:1; min-width:0; }
      #rsRandBtn { flex-shrink:0; width:32px; height:32px; background:rgba(255,255,255,0.07); border:1px solid rgba(255,255,255,0.13); border-radius:9px; cursor:pointer; font-size:15px; display:flex; align-items:center; justify-content:center; transition:background .18s, transform .12s; }
      #rsRandBtn:hover { background:rgba(91,140,255,0.22); border-color:rgba(91,140,255,0.45); transform:rotate(20deg) scale(1.1); }
    </style>
    <div id="rsPanelHeader">
      <span id="rsPanelTitle">Tsk - Fake Robux</span>
      <div class="rs-hdr-btns">
        <button class="rs-hdr-btn" id="rsSettingsBtn" title="Settings">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="3"/>
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
          </svg>
        </button>
        <button class="rs-hdr-btn" id="rsCloseBtn" title="Close">✕</button>
      </div>
    </div>
    <div id="rsCollapseWrap">
      <div class="rs-view" id="rsMainView">
        <div>
          <div class="rsLabel">Balance <span id="rsAmtDisplay">0</span></div>
          <div class="rs-input-row">
            <input id="rsRobuxInput" type="number" placeholder="0" min="0" step="10000">
            <button id="rsRandBtn" title="Valor aleatório (800K–5M">🎲</button>
          </div>
        </div>
        <button id="rsApply">Apply</button>
      </div>
      <div class="rs-view" id="rsSettingsView">
        <div class="rs-settings-top">
          <button id="rsBackBtn">
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            Back
          </button>
          <div id="rsPresetTitle">Set Preset</div>
        </div>
        <div class="rs-divider"></div>
        <div class="rsPresetGrid">
          <input class="rsPresetInput" data-idx="0" type="number" min="1">
          <input class="rsPresetInput" data-idx="1" type="number" min="1">
          <input class="rsPresetInput" data-idx="2" type="number" min="1">
          <input class="rsPresetInput" data-idx="3" type="number" min="1">
        </div>
        <div class="rs-divider"></div>
        <div class="rs-tts-section">
          <div class="rs-ia-row">
            <span class="rs-ia-label">Voice</span>
            <label class="rs-toggle">
              <input type="checkbox" id="rsTtsToggle">
              <span class="rs-toggle-track"></span>
            </label>
          </div>
          <div class="rs-ia-row" style="margin-top: 3px; margin-bottom: 2px;">
            <span class="rs-ia-label" style="font-size: 8px;">Saída de Áudio</span>
          </div>
          <div class="rs-voice-mode-row" style="margin-bottom: 5px;">
            <button class="rs-voice-mode-btn active" id="rsOutChrome">💻 Chrome</button>
            <button class="rs-voice-mode-btn" id="rsOutMic">🎤 Mic (Virtual)</button>
          </div>
          <div class="rs-voice-mode-row">
            <button class="rs-voice-mode-btn active" id="rsModeIA">🤖 IA Voice</button>
            <button class="rs-voice-mode-btn" id="rsModeMy">🎙️ Minha Voz</button>
          </div>
          <div id="rsIaSection">
            <select id="rsTtsVoice"><option value="">Auto (pt-BR)</option></select>
            <div class="rs-slider-row">
              <span>Vol</span><input type="range" id="rsTtsVol" min="0.1" max="1" step="0.1" value="1">
            </div>
            <div class="rs-slider-row">
              <span>Vel</span><input type="range" id="rsTtsRate" min="0.5" max="2" step="0.1" value="0.9">
            </div>
          </div>
          <div id="rsTtsEndLiveSlot" class="rs-tts-slot" style="border-color: rgba(255,80,80,0.3); background: rgba(255,80,80,0.03); margin-bottom: 4px;">
            <div class="rs-tts-slot-header">
              <span class="rs-tts-slot-label" style="color: rgba(255,100,100,0.9);">🛑 Fim de Live (10s)</span>
            </div>
            <textarea id="rsTtsEndLiveTxt" class="rs-tts-slot-txt" rows="2" placeholder="Ex: Atenção, a live vai encerrar..."></textarea>
            <div class="rs-tts-slot-rec" id="rsEndLiveRecRow" style="display:none;">
              <button id="rsEndLiveRecBtn" class="rs-rec-btn rec-idle">⏺ Gravar</button>
              <button id="rsEndLivePlayBtn" class="rs-rec-play" style="display:none;">▶ Ouvir</button>
              <span id="rsEndLiveStatus" class="rs-rec-status"></span>
            </div>
          </div>
          <div id="rsTtsSlotList"></div>
          <button id="rsTtsAddBtn">+ Adicionar fala</button>
        </div>
      </div>
    </div>`;

  function slideViews(hideView, showView, direction) {
    hideView.style.transition = 'opacity 0.14s ease, transform 0.14s ease';
    hideView.style.opacity = '0';
    hideView.style.transform = 'translateX(' + (direction * 11) + 'px)';
    hideView.style.pointerEvents = 'none';
    setTimeout(() => {
      hideView.style.display = 'none';
      hideView.style.transition = '';
      hideView.style.transform = '';
      showView.style.display = 'flex';
      showView.style.opacity = '0';
      showView.style.transform = 'translateX(' + (-direction * 11) + 'px)';
      showView.style.pointerEvents = '';
      requestAnimationFrame(() => {
        showView.style.transition = 'opacity 0.14s ease, transform 0.14s ease';
        showView.style.opacity = '1';
        showView.style.transform = 'translateX(0)';
      });
    }, 140);
  }

  function createPanel() {
    if (document.getElementById('rsPanel')) return;

    const panel = document.createElement('div');
    panel.id = 'rsPanel';
    panel.innerHTML = PANEL_HTML;
    document.body.appendChild(panel);

    const robuxInput = panel.querySelector('#rsRobuxInput');
    const applyButton = panel.querySelector('#rsApply');
    const closeButton = panel.querySelector('#rsCloseBtn');
    const settingsButton = panel.querySelector('#rsSettingsBtn');
    const backButton = panel.querySelector('#rsBackBtn');
    const mainView = panel.querySelector('#rsMainView');
    const settingsView = panel.querySelector('#rsSettingsView');

    robuxInput.value = fakeRobux;
    const display = document.getElementById('rsAmtDisplay');
    if (display) display.textContent = formatRobux(fakeRobux);

    const randBtn = panel.querySelector('#rsRandBtn');
    if (randBtn) {
      randBtn.onclick = () => {
        const min = 800000;
        const max = 5000000;
        const rand = Math.floor(Math.random() * (max - min + 1)) + min;
        robuxInput.value = rand;
        updateBalance(rand);
        applyButton.textContent = 'Applied ✓';
        setTimeout(() => { applyButton.textContent = 'Apply'; }, 1000);
      };
    }

    settingsButton.onclick = () => {
      settingsButton.classList.add('rs-active');
      slideViews(mainView, settingsView, -1);
      scrollTtsToBottom();
    };
    backButton.onclick = () => {
      settingsButton.classList.remove('rs-active');
      slideViews(settingsView, mainView, 1);
    };
    closeButton.onclick = () => {
      panel.remove();
      chrome.storage.local.set({ rsPanelClosed: true });
    };

    robuxInput.addEventListener('input', () => {
      const amt = document.getElementById('rsAmtDisplay');
      if (amt) amt.textContent = formatRobux(robuxInput.value || '0');
    });
    robuxInput.addEventListener('change', () => {
      updateBalance(robuxInput.value);
      applyButton.textContent = 'Saved ✓';
      setTimeout(() => { applyButton.textContent = 'Apply'; }, 1000);
    });
    applyButton.onclick = () => {
      updateBalance(robuxInput.value);
      applyButton.textContent = 'Applied ✓';
      setTimeout(() => { applyButton.textContent = 'Apply'; }, 1000);
    };

    panel.querySelectorAll('.rsPresetInput').forEach(input => {
      const index = parseInt(input.dataset.idx, 10);
      input.value = presets[index];
      input.addEventListener('change', () => {
        const value = Math.max(1, parseInt(input.value, 10) || 1);
        input.value = value;
        presets[index] = value;
        savePresets();
      });
    });

    // Wiring dos controles de TTS
    const ttsToggleEl = panel.querySelector('#rsTtsToggle');
    if (ttsToggleEl) {
      ttsToggleEl.checked = ttsEnabled;
      ttsToggleEl.addEventListener('change', () => {
        ttsEnabled = ttsToggleEl.checked;
        chrome.storage.local.set({ ttsEnabled });
      });
    }

    // Wiring da Saída de Áudio (Chrome vs Microfone/Cabo Virtual)
    const outChromeBtn = panel.querySelector('#rsOutChrome');
    const outMicBtn = panel.querySelector('#rsOutMic');
    function applyAudioOutputUI() {
      const isChrome = (ttsOutputMode === 'chrome');
      outChromeBtn && outChromeBtn.classList.toggle('active', isChrome);
      outMicBtn && outMicBtn.classList.toggle('active', !isChrome);
    }
    if (outChromeBtn) outChromeBtn.onclick = () => { ttsOutputMode = 'chrome'; chrome.storage.local.set({ ttsOutputMode }); applyAudioOutputUI(); };
    if (outMicBtn) {
      outMicBtn.onclick = async () => {
        // Solicita acesso ao microfone uma vez para obter permissão para listar nomes de dispositivos
        try {
          await navigator.mediaDevices.getUserMedia({ audio: true });
        } catch (e) {}
        ttsOutputMode = 'mic';
        chrome.storage.local.set({ ttsOutputMode });
        applyAudioOutputUI();
      };
    }
    applyAudioOutputUI();

    // Seletor de modo: IA ou Minha Voz
    const modeIABtn  = panel.querySelector('#rsModeIA');
    const modeMYBtn  = panel.querySelector('#rsModeMy');
    const iaSection  = panel.querySelector('#rsIaSection');
    function applyModeUI() {
      const isIA = (ttsMode === 'ia');
      modeIABtn && modeIABtn.classList.toggle('active', isIA);
      modeMYBtn && modeMYBtn.classList.toggle('active', !isIA);
      if (iaSection) iaSection.style.display = isIA ? '' : 'none';
      // Re-renderiza slots pra mostrar/esconder controles de gravação
      renderTtsSlots();
    }
    if (modeIABtn) modeIABtn.onclick = () => { ttsMode = 'ia'; chrome.storage.local.set({ ttsMode }); applyModeUI(); };
    if (modeMYBtn) modeMYBtn.onclick = () => { ttsMode = 'myvoice'; chrome.storage.local.set({ ttsMode }); applyModeUI(); };

    // Fim de Live handler
    const endLiveTxt = panel.querySelector('#rsTtsEndLiveTxt');
    const endLiveRecRow = panel.querySelector('#rsEndLiveRecRow');
    const endLiveRecBtn = panel.querySelector('#rsEndLiveRecBtn');
    const endLivePlayBtn = panel.querySelector('#rsEndLivePlayBtn');
    const endLiveStatus = panel.querySelector('#rsEndLiveStatus');
    let activeEndLiveRec = null;

    endLiveTxt.value = ttsEndLiveText || '';
    endLiveTxt.addEventListener('change', () => {
      ttsEndLiveText = endLiveTxt.value.trim();
      chrome.storage.local.set({ ttsEndLiveText });
    });

    function updateEndLiveUI() {
      endLiveRecRow.style.display = (ttsMode === 'myvoice') ? 'flex' : 'none';
      const hasRec = !!ttsEndLiveRecording;
      endLiveRecBtn.className = 'rs-rec-btn ' + (hasRec ? 'rec-saved' : 'rec-idle');
      endLiveRecBtn.textContent = hasRec ? '✓ Gravado' : '⏺ Gravar';
      endLivePlayBtn.style.display = hasRec ? 'inline-flex' : 'none';
      endLiveStatus.textContent = hasRec ? 'áudio salvo' : '';
    }
    
    endLiveRecBtn.onclick = async () => {
      if (activeEndLiveRec) {
        activeEndLiveRec.stop();
        return;
      }
      if (ttsEndLiveRecording) {
        ttsEndLiveRecording = null;
        chrome.storage.local.set({ ttsEndLiveRecording });
        updateEndLiveUI();
        return;
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        const mr = new MediaRecorder(stream);
        activeEndLiveRec = mr;
        const chunks = [];
        mr.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };
        mr.onstart = () => {
          endLiveRecBtn.className = 'rs-rec-btn rec-recording';
          endLiveRecBtn.textContent = '⏹ Parar';
          endLiveStatus.textContent = '🔴 gravando...';
        };
        mr.onstop = () => {
          activeEndLiveRec = null;
          stream.getTracks().forEach(t => t.stop());
          const blob = new Blob(chunks, { type: mr.mimeType || 'audio/webm' });
          const reader = new FileReader();
          reader.onload = () => {
            ttsEndLiveRecording = reader.result;
            chrome.storage.local.set({ ttsEndLiveRecording });
            updateEndLiveUI();
          };
          reader.readAsDataURL(blob);
        };
        mr.start();
      } catch (err) {}
    };

    endLivePlayBtn.onclick = () => {
      if (ttsEndLiveRecording) playCustomVoice(ttsEndLiveRecording);
    };

    // Sistema de falas ilimitadas
    const slotList = panel.querySelector('#rsTtsSlotList');
    function saveTtsSlots() {
      chrome.storage.local.set({ ttsSlots: JSON.stringify(ttsSlots) });
    }
    function saveTtsRecordings() {
      chrome.storage.local.set({ ttsRecordings: JSON.stringify(ttsRecordings) });
    }

    // Gravadores ativos (um por slot, para não misturar)
    const _activeRecorders = {};

    function renderTtsSlots() {
      if (!slotList) return;
      slotList.innerHTML = '';
      ttsSlots.forEach((slot, i) => {
        const wrap = document.createElement('div');
        wrap.className = 'rs-tts-slot';

        const header = document.createElement('div');
        header.className = 'rs-tts-slot-header';
        const lbl = document.createElement('span');
        lbl.className = 'rs-tts-slot-label';
        lbl.textContent = 'Fala ' + (i + 1);
        const delBtn = document.createElement('button');
        delBtn.className = 'rs-tts-slot-del';
        delBtn.textContent = '✕';
        delBtn.title = 'Remover fala';
        delBtn.onclick = () => {
          if (ttsSlots.length <= 1) return;
          ttsSlots.splice(i, 1);
          // Reorganiza os índices das gravações
          const newRecordings = {};
          for (let j = 0; j <= ttsSlots.length; j++) {
            if (j < i && ttsRecordings[j]) newRecordings[j] = ttsRecordings[j];
            else if (j > i && ttsRecordings[j]) newRecordings[j - 1] = ttsRecordings[j];
          }
          ttsRecordings = newRecordings;
          saveTtsSlots();
          saveTtsRecordings();
          renderTtsSlots();
        };
        header.append(lbl, delBtn);

        const txt = document.createElement('textarea');
        txt.className = 'rs-tts-slot-txt';
        txt.rows = 2;
        txt.placeholder = 'Texto da fala...';
        txt.value = slot.text || '';
        txt.addEventListener('change', () => {
          ttsSlots[i].text = txt.value.trim();
          saveTtsSlots();
        });

        const intervalRow = document.createElement('div');
        intervalRow.className = 'rs-tts-slot-interval';
        const inp = document.createElement('input');
        inp.type = 'number';
        inp.min = '1';
        inp.max = '999';
        inp.value = slot.interval || 5;
        inp.addEventListener('change', () => {
          const val = Math.max(1, parseInt(inp.value, 10) || 5);
          inp.value = val;
          ttsSlots[i].interval = val;
          saveTtsSlots();
        });
        intervalRow.append('A cada ', inp, ' entregas');

        wrap.append(header, txt, intervalRow);

        // ---- Seção de gravação (só aparece no modo Minha Voz) ----
        const recRow = document.createElement('div');
        recRow.className = 'rs-tts-slot-rec';
        recRow.style.display = (ttsMode === 'myvoice') ? 'flex' : 'none';

        const hasRec = !!ttsRecordings[i];
        const recBtn = document.createElement('button');
        recBtn.className = 'rs-rec-btn ' + (hasRec ? 'rec-saved' : 'rec-idle');
        recBtn.textContent = hasRec ? '✓ Gravado' : '⏺ Gravar';
        recBtn.title = hasRec ? 'Clique para regravar' : 'Gravar voz';

        const playBtn = document.createElement('button');
        playBtn.className = 'rs-rec-play';
        playBtn.textContent = '▶ Ouvir';
        playBtn.style.display = hasRec ? 'inline-flex' : 'none';

        const statusTxt = document.createElement('span');
        statusTxt.className = 'rs-rec-status';
        statusTxt.textContent = hasRec ? 'áudio salvo' : '';

        // Lógica de gravação
        recBtn.onclick = async () => {
          // Se já estiver gravando este slot → para
          if (_activeRecorders[i]) {
            _activeRecorders[i].stop();
            return;
          }
          // Se tem gravação → confirma regravação
          if (ttsRecordings[i]) {
            recBtn.className = 'rs-rec-btn rec-idle';
            recBtn.textContent = '⏺ Gravar';
            playBtn.style.display = 'none';
            statusTxt.textContent = '';
            delete ttsRecordings[i];
            saveTtsRecordings();
            return;
          }
          // Pede permissão e começa a gravar
          try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            const mr = new MediaRecorder(stream);
            _activeRecorders[i] = mr;
            const chunks = [];
            mr.ondataavailable = e => { if (e.data.size > 0) chunks.push(e.data); };
            mr.onstart = () => {
              recBtn.className = 'rs-rec-btn rec-recording';
              recBtn.textContent = '⏹ Parar';
              statusTxt.textContent = '🔴 gravando...';
            };
            mr.onstop = () => {
              delete _activeRecorders[i];
              stream.getTracks().forEach(t => t.stop());
              const blob = new Blob(chunks, { type: mr.mimeType || 'audio/webm' });
              const reader = new FileReader();
              reader.onload = () => {
                ttsRecordings[i] = reader.result; // data URL base64
                saveTtsRecordings();
                recBtn.className = 'rs-rec-btn rec-saved';
                recBtn.textContent = '✓ Gravado';
                recBtn.title = 'Clique para regravar';
                playBtn.style.display = 'inline-flex';
                statusTxt.textContent = 'áudio salvo';
              };
              reader.readAsDataURL(blob);
            };
            mr.start();
          } catch (err) {
            statusTxt.textContent = '❌ Sem permissão de mic';
          }
        };

        playBtn.onclick = () => {
          if (ttsRecordings[i]) playCustomVoice(ttsRecordings[i]);
        };

        recRow.append(recBtn, playBtn, statusTxt);
        wrap.append(recRow);

        slotList.appendChild(wrap);
      });
    }
    // Inicializa modo UI depois de renderTtsSlots estar definida
    applyModeUI();
    updateEndLiveUI();

    function scrollTtsToBottom() {
      requestAnimationFrame(() => {
        if (slotList) slotList.scrollTop = slotList.scrollHeight;
        const collapseWrap = panel.querySelector('#rsCollapseWrap');
        if (collapseWrap) collapseWrap.scrollTop = collapseWrap.scrollHeight;
      });
    }

    const addSlotBtn = panel.querySelector('#rsTtsAddBtn');
    if (addSlotBtn) {
      addSlotBtn.onclick = () => {
        ttsSlots.push({ text: '', interval: 5 });
        saveTtsSlots();
        renderTtsSlots();
        scrollTtsToBottom();
      };
    }

    // Seletor de voz — popula com todas as vozes disponíveis
    const ttsVoiceEl = panel.querySelector('#rsTtsVoice');
    const ttsVolEl = panel.querySelector('#rsTtsVol');
    const ttsRateEl = panel.querySelector('#rsTtsRate');
    
    if (ttsVolEl) {
      ttsVolEl.value = ttsVolume;
      ttsVolEl.addEventListener('input', () => {
        ttsVolume = parseFloat(ttsVolEl.value);
        chrome.storage.local.set({ ttsVolume });
      });
    }
    if (ttsRateEl) {
      ttsRateEl.value = ttsRate;
      ttsRateEl.addEventListener('input', () => {
        ttsRate = parseFloat(ttsRateEl.value);
        chrome.storage.local.set({ ttsRate });
      });
    }

    if (ttsVoiceEl) {
      const populateVoices = () => {
        const voices = window.speechSynthesis ? window.speechSynthesis.getVoices() : [];
        ttsVoiceEl.innerHTML = '<option value="">Auto (pt-BR)</option>';
        voices.forEach(v => {
          const opt = document.createElement('option');
          opt.value = v.name;
          opt.textContent = v.name + ' (' + v.lang + ')';
          if (v.name === ttsVoiceName) opt.selected = true;
          ttsVoiceEl.appendChild(opt);
        });
      };
      populateVoices();
      if (window.speechSynthesis) window.speechSynthesis.addEventListener('voiceschanged', populateVoices);
      ttsVoiceEl.addEventListener('change', () => {
        ttsVoiceName = ttsVoiceEl.value;
        chrome.storage.local.set({ ttsVoiceName });
      });
    }

    let dragging = false;
    let offsetX = 0;
    let offsetY = 0;
    panel.querySelector('#rsPanelHeader').addEventListener('mousedown', event => {
      dragging = true;
      const rect = panel.getBoundingClientRect();
      offsetX = event.clientX - rect.left;
      offsetY = event.clientY - rect.top;
    });
    document.addEventListener('mousemove', event => {
      if (!dragging) return;
      panel.style.right = 'auto';
      panel.style.bottom = 'auto';
      panel.style.left = (event.clientX - offsetX) + 'px';
      panel.style.top = (event.clientY - offsetY) + 'px';
    });
    document.addEventListener('mouseup', () => { dragging = false; });
  }

  function reapplyBalanceLabels() {
    const display = formatRobux(fakeRobux || '0');
    document.querySelectorAll('.text-label-medium.content-emphasis').forEach(el => {
      const text = (el.textContent || '').trim();
      if (text && text !== display && looksLikeRobux(text)) el.textContent = display;
    });
  }

  function cleanPurchaseModal() {
    const heading = document.getElementById('rbx-unified-purchase-heading');
    if (!heading) return;
    const fake = formatThousands(fakeRobux) || '0';
    heading.querySelectorAll('span.text-robux').forEach(el => { if (el.textContent !== fake) el.textContent = fake; });
    document.querySelectorAll('.rounded-xxlarge.radius-medium.border.padding-medium').forEach(el => el.remove());
  }

  function refreshFromStorage() {
    chrome.storage.local.get(['fakeRobux'], data => {
      const value = (data && data.fakeRobux) || fakeRobux;
      if (value !== fakeRobux) updateBalance(value);
      else applyBalance(fakeRobux);
    });
    bindFriendOptions();
    injectGiftButton();
    cleanPurchaseModal();
  }

  function whenBodyReady(callback) {
    if (document.body) {
      callback();
      return;
    }
    const observer = new MutationObserver(() => {
      if (document.body) {
        observer.disconnect();
        callback();
      }
    });
    observer.observe(document.documentElement, { childList: true });
  }

  // Bloqueia o modal "Initiating Roblox" que quebra o fluxo de automação
  function blockRobloxLaunchDialog() {
    // Bloqueia window.open para protocolo roblox://, roblox-player:// e fishstrap://
    const _origOpen = window.open;
    window.open = function (url) {
      if (url && /^(?:roblox(?:-player)?|fishstrap):\/\//i.test(String(url))) return null;
      return _origOpen.apply(this, arguments);
    };

    // Intercepta criação de <a> ou <iframe> com protocolo roblox:// ou fishstrap://
    const _origCreateElement = document.createElement.bind(document);
    document.createElement = function (tag) {
      const el = _origCreateElement(tag);
      const tagLower = (tag || '').toLowerCase();
      if (tagLower === 'a' || tagLower === 'iframe') {
        const _origSetAttr = el.setAttribute.bind(el);
        el.setAttribute = function (name, value) {
          const attr = (name || '').toLowerCase();
          if ((attr === 'href' || attr === 'src') && value && /^(?:roblox(?:-player)?|fishstrap):\/\//i.test(String(value))) return;
          return _origSetAttr(name, value);
        };
      }
      return el;
    };

    // Remove o modal "Initiating Roblox" sempre que ele aparecer no DOM
    function removeRobloxLaunchModal() {
      // Seletores conhecidos do modal de launch do Roblox
      [
        '#roblox-linkcard',
        '[data-testid="game-play-modal"]',
        '[data-testid*="launch"]',
        '.modal-backdrop'
      ].forEach(sel => { try { document.querySelectorAll(sel).forEach(el => el.remove()); } catch (e) { } });

      // Busca por texto "Initiating Roblox" em elementos fixos/absolutos
      document.querySelectorAll('div, section, aside').forEach(el => {
        if (!el || !el.isConnected) return;
        const txt = (el.textContent || '').trim();
        if (
          (txt.includes('Initiating Roblox') || txt.includes('Starting Roblox') || txt.includes('Launching Roblox')) &&
          txt.length < 400
        ) {
          const cs = window.getComputedStyle(el);
          if (cs.position === 'fixed' || cs.position === 'absolute' || el.style.position === 'fixed') {
            el.remove();
          }
        }
      });
    }

    // Observa o body para remover o modal assim que ele aparecer
    const launchObserver = new MutationObserver(removeRobloxLaunchModal);
    launchObserver.observe(document.body || document.documentElement, { childList: true, subtree: true });

    // Passa mais uma vez no load por garantia
    removeRobloxLaunchModal();
  }

  function autoCloseFoundationCloseButton() {
    const seletorDoBotao = 'button.foundation-web-close-affordance[aria-label="Close"]';

    function tentarClicar() {
      const botao = document.querySelector(seletorDoBotao);
      if (botao) {
        botao.click();
      }
    }

    tentarClicar();

    const observer = new MutationObserver(mutationsList => {
      for (const mutation of mutationsList) {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          tentarClicar();
          break;
        }
      }
    });

    const targetNode = document.body || document.documentElement;
    if (targetNode) {
      observer.observe(targetNode, { childList: true, subtree: true });
    }
  }

  function start(data) {
    fakeRobux = data.fakeRobux || data.Robux || '0';
    if (data.rsPresets) {
      try { presets = JSON.parse(data.rsPresets); } catch (e) {}
    }
    if (data.ttsEnabled !== undefined) ttsEnabled = data.ttsEnabled;
    if (data.ttsVolume !== undefined) ttsVolume = data.ttsVolume;
    if (data.ttsRate !== undefined) ttsRate = data.ttsRate;
    if (data.ttsOutputMode) ttsOutputMode = data.ttsOutputMode;
    if (data.ttsMode) ttsMode = data.ttsMode;
    if (data.ttsSlots) {
      try { ttsSlots = JSON.parse(data.ttsSlots); } catch (e) {}
    }
    if (data.ttsRecordings) {
      try { ttsRecordings = JSON.parse(data.ttsRecordings); } catch (e) {}
    }
    if (data.ttsVoiceName) ttsVoiceName = data.ttsVoiceName;
    if (data.ttsEndLiveText) ttsEndLiveText = data.ttsEndLiveText;
    if (data.ttsEndLiveRecording) ttsEndLiveRecording = data.ttsEndLiveRecording;
    if (data.keyboardSoundsEnabled !== undefined) keyboardSoundsEnabled = !!data.keyboardSoundsEnabled;
    if (data.keyboardVolume !== undefined) keyboardVolume = parseFloat(data.keyboardVolume);
    if (data.customKeySounds) customKeySounds = data.customKeySounds;

    blockRobloxLaunchDialog();
    autoCloseFoundationCloseButton();
    whenBodyReady(() => {
      new MutationObserver(() => {
        reapplyBalanceLabels();
        cleanPurchaseModal();
        injectGiftButton();
      }).observe(document.body, { childList: true, subtree: true });
      applyBalance(fakeRobux);
      cleanPurchaseModal();
      injectGiftButton();
      setInterval(refreshFromStorage, 250);
      setInterval(pollLiveQueue, 1800);
      connectLiveQueue();
      if (!(data && data.rsPanelClosed)) createPanel();

      document.addEventListener('keydown', event => {
        if (event.ctrlKey && (event.key || '').toLowerCase() === 'm') {
          event.preventDefault();
          runQueueTest();
          return;
        }
        if (event.key !== 'Insert') return;
        const existing = document.getElementById('rsPanel');
        if (existing) {
          existing.remove();
          chrome.storage.local.set({ rsPanelClosed: true });
        } else {
          chrome.storage.local.set({ rsPanelClosed: false });
          createPanel();
        }
      });
    });
  }

  chrome.storage.local.get(['licenseValid', 'licenseKey', 'fakeRobux', 'rsPanelClosed', 'Robux', 'rsPresets', 'ttsEnabled', 'ttsVolume', 'ttsRate', 'ttsMode', 'ttsSlots', 'ttsRecordings', 'ttsVoiceName', 'ttsEndLiveText', 'ttsEndLiveRecording', 'ttsOutputMode', 'keyboardSoundsEnabled', 'keyboardVolume', 'customKeySounds'], license => {
    if (!license || !license.licenseValid) return;
    start(license);
  });

})();
