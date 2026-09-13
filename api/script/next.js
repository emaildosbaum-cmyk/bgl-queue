// Vercel Serverless Function: Retorna o próximo nick para o Roblox Script
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

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
  const token = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();

  if (!token) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ error: "Token não fornecido. Passe ?token=SEU_TOKEN" }));
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`
  };

  try {
    // 1. Identifica usuário pelo script_token
    const profileResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?script_token=eq.${encodeURIComponent(token)}&select=discord_id,username`, { headers });
    const profiles = await profileResp.json();
    if (!profiles || profiles.length === 0) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Token inválido" }));
    }
    const userId = profiles[0].discord_id;

    // 2. Verifica se a fila está pausada nas configs do usuário
    const cfgResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(userId)}&select=operation_mode,queue_paused`, { headers });
    const configs = await cfgResp.json();
    if (configs && configs.length > 0) {
      const cfg = configs[0];
      if (cfg.queue_paused || cfg.operation_mode === "PAUSED" || cfg.operation_mode === "FALA" || cfg.operation_mode === "MINI") {
        res.statusCode = 204;
        return res.end();
      }
    }

    // 3. Puxa o próximo nick pendente da fila deste usuário
    const queueResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(userId)}&status=eq.pending&order=id.asc&limit=1`, { headers });
    const queueItems = await queueResp.json();
    if (!queueItems || queueItems.length === 0) {
      res.statusCode = 204;
      return res.end();
    }

    const item = queueItems[0];

    // 4. Marca como processando para não repetir
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?id=eq.${item.id}`, {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "processing" })
    });

    // 5. Atualiza o Passo 1 no Stepper
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(userId)}`, {
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

    res.statusCode = 200;
    return res.end(JSON.stringify({
      username: item.nick,
      fruit: "Random",
      source: item.sender_id || "queue",
      id: item.id
    }));
  } catch (err) {
    console.error("Erro no /next:", err);
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
