// Vercel Serverless Function: GET retorna configs do script, POST salva configs
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

function cleanToken(raw) {
  if (!raw) return "";
  let tok = String(raw).trim().replace(/^["']|["']$/g, "").trim();
  if (tok.includes("token=")) {
    const match = tok.match(/token=([^&]+)/);
    if (match) tok = decodeURIComponent(match[1]).trim();
  } else if (tok.includes("uid=")) {
    const match = tok.match(/uid=([^&]+)/);
    if (match) tok = decodeURIComponent(match[1]).trim();
  }
  return tok.replace(/^["']|["']$/g, "").trim();
}

async function resolveUserId(token, headers) {
  const filter = `or=(script_token.eq.${encodeURIComponent(token)},discord_id.eq.${encodeURIComponent(token)},username.ilike.${encodeURIComponent(token)})`;
  const profileResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?${filter}&select=discord_id,username,script_token`, { headers });
  const profiles = await profileResp.json();
  if (!profiles || profiles.length === 0) return null;
  return profiles[0];
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
    return res.end(JSON.stringify({ error: "Token não fornecido" }));
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
  };

  try {
    const profile = await resolveUserId(token, headers);
    if (!profile) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Chave não encontrada no sistema" }));
    }
    const userId = profile.discord_id;
    const userName = profile.username || userId;
    const canonicalToken = profile.script_token || token;

    // ── POST: salva configurações gerais ──────────────────────────
    if (req.method === "POST") {
      let body = {};
      try {
        const chunks = [];
        await new Promise((resolve, reject) => {
          req.on("data", c => chunks.push(c));
          req.on("end", resolve);
          req.on("error", reject);
        });
        body = JSON.parse(Buffer.concat(chunks).toString() || "{}");
      } catch (e) {}

      // Busca general_settings atual para fazer merge (não sobrescreve outros campos)
      const cfgResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(userId)}&select=general_settings`, { headers });
      const cfgs = await cfgResp.json();
      const existingGen = (cfgs && cfgs[0] && cfgs[0].general_settings) || {};

      const newGen = Object.assign({}, existingGen);
      // Aceita qualquer campo enviado: item_name, item_price, mock_balance, post_delivery_delay...
      const allowed = ["item_name", "item_price", "mock_balance", "post_delivery_delay"];
      allowed.forEach(k => { if (body[k] !== undefined) newGen[k] = String(body[k]); });

      // Upsert na tabela bgl_user_configs
      const upsertResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(userId)}`, {
        method: "PATCH",
        headers: { ...headers, "Prefer": "return=minimal" },
        body: JSON.stringify({ general_settings: newGen, updated_at: new Date().toISOString() })
      });

      if (upsertResp.status === 404 || upsertResp.status === 406) {
        // Usuário não tem linha ainda — cria
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs`, {
          method: "POST",
          headers: { ...headers, "Prefer": "return=minimal" },
          body: JSON.stringify({ discord_id: userId, general_settings: newGen, updated_at: new Date().toISOString() })
        });
      }

      res.statusCode = 200;
      return res.end(JSON.stringify({ ok: true, saved: newGen }));
    }

    // ── GET: retorna configurações ────────────────────────────────
    const cfgResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(userId)}&select=*`, { headers });
    const configs = await cfgResp.json();
    const userCfg = (configs && configs[0]) || {};

    const stepTimeouts = userCfg.step_timeouts || {
      step1: 5, step2: 5, step3: 5, step4: 6, step5: 7, step6: 5
    };
    const gen = userCfg.general_settings || {};

    res.statusCode = 200;
    return res.end(JSON.stringify({
      user_id: userId,
      username: userName,
      script_token: canonicalToken,
      operation_mode: userCfg.operation_mode || "FULL",
      auto_send: userCfg.operation_mode === "FULL" || userCfg.operation_mode === "ENTREGA",
      step_timeouts: stepTimeouts,
      mock_balance: gen.mock_balance || "5,420",
      item_name: gen.item_name || "Rocket",
      item_price: gen.item_price || "100",
      post_delivery_delay: gen.post_delivery_delay || 2.0,
      live_proof: userCfg.live_proof || { enabled: true, duration: 4.0, message: "Tô ao vivo rapaziada, não é gravado!" }
    }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
