// Vercel Serverless Function: Retorna o próximo nick para o Roblox Script
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

function cleanToken(raw) {
  if (!raw) return "";
  let tok = String(raw).trim().replace(/^[\"']|[\"']$/g, "").trim();
  if (tok.includes("token=")) {
    const match = tok.match(/token=([^&]+)/);
    if (match) tok = decodeURIComponent(match[1]).trim();
  } else if (tok.includes("uid=")) {
    const match = tok.match(/uid=([^&]+)/);
    if (match) tok = decodeURIComponent(match[1]).trim();
  }
  return tok.replace(/^[\"']|[\"']$/g, "").trim();
}

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const urlObj = new URL(req.url, "http://localhost");
  const rawToken = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();
  const token = cleanToken(rawToken);

  if (!token) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ error: "Token não fornecido. Passe ?token=SEU_TOKEN" }));
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": "Bearer " + SUPABASE_KEY
  };

  try {
    // 1. Identifica usuário por script_token, discord_id ou username
    const filter = "or=(script_token.eq." + encodeURIComponent(token) + ",discord_id.eq." + encodeURIComponent(token) + ",username.ilike." + encodeURIComponent(token) + ")";
    const profileResp = await fetch(SUPABASE_URL + "/rest/v1/bgl_user_profiles?" + filter + "&select=discord_id,username", { headers });
    const profiles = await profileResp.json();
    if (!profiles || profiles.length === 0) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Chave não encontrada no sistema" }));
    }
    const userId = profiles[0].discord_id;

    // 2. Verifica se a fila está pausada nas configs do usuário & pega fruta configurada
    let configuredFruit = "Rocket";
    const cfgResp = await fetch(SUPABASE_URL + "/rest/v1/bgl_user_configs?discord_id=eq." + encodeURIComponent(userId) + "&select=operation_mode,queue_paused,general_settings", { headers });
    const configs = await cfgResp.json();
    if (configs && configs.length > 0) {
      const cfg = configs[0];
      if (cfg.queue_paused || cfg.operation_mode === "PAUSED" || cfg.operation_mode === "FALA" || cfg.operation_mode === "MINI") {
        res.statusCode = 204;
        return res.end();
      }
      if (cfg.general_settings && cfg.general_settings.item_name) {
        const item = String(cfg.general_settings.item_name).trim();
        if (item && item.toLowerCase() !== "generic" && item.toLowerCase() !== "fruit" && item !== "Sword of Destiny") {
          configuredFruit = item;
        }
      }
    }

    // 2.1 Watchdog de fila: destrava itens em processing há mais de 45s
    try {
      const staleTime = new Date(Date.now() - 45000).toISOString();
      await fetch(SUPABASE_URL + "/rest/v1/bgl_user_queues?user_id=eq." + encodeURIComponent(userId) + "&status=eq.processing&created_at=lt." + staleTime, {
        method: "PATCH",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({ status: "cancelled" })
      });
    } catch(e) {}

    // 3. Puxa o próximo nick pendente da fila deste usuário
    const queueResp = await fetch(SUPABASE_URL + "/rest/v1/bgl_user_queues?user_id=eq." + encodeURIComponent(userId) + "&status=eq.pending&order=id.asc&limit=1", { headers });
    const queueItems = await queueResp.json();
    if (!queueItems || queueItems.length === 0) {
      res.statusCode = 204;
      return res.end();
    }

    const item = queueItems[0];

    // 4. Marca como processando para não repetir
    await fetch(SUPABASE_URL + "/rest/v1/bgl_user_queues?id=eq." + item.id, {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "processing" })
    });

    // 5. Atualiza o Passo 1 no Stepper
    await fetch(SUPABASE_URL + "/rest/v1/bgl_user_steps?user_id=eq." + encodeURIComponent(userId), {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        current_step: 1,
        step_name: "Recebeu nick",
        target_nick: item.nick,
        status: "in_progress",
        updated_at: new Date().toISOString()
      })
    });

    const finalFruit = item.fruit || configuredFruit || "Rocket";

    res.statusCode = 200;
    return res.end(JSON.stringify({
      username: item.nick,
      fruit: finalFruit,
      source: item.sender_id || "queue",
      id: item.id
    }));
  } catch (err) {
    console.error("Erro no /next:", err);
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};