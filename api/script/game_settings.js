// Vercel Serverless Function: Retorna as configurações do Roblox Script
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const urlObj = new URL(req.url, "http://localhost");
  const token = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();

  if (!token) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ error: "Token não fornecido" }));
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`
  };

  try {
    const profileResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?script_token=eq.${encodeURIComponent(token)}&select=discord_id`, { headers });
    const profiles = await profileResp.json();
    if (!profiles || profiles.length === 0) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Token inválido" }));
    }
    const userId = profiles[0].discord_id;

    const cfgResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(userId)}&select=*`, { headers });
    const configs = await cfgResp.json();
    const userCfg = (configs && configs[0]) || {};

    const stepTimeouts = userCfg.step_timeouts || {
      step1: 5, step2: 5, step3: 5, step4: 6, step5: 7, step6: 5
    };
    const gen = userCfg.general_settings || {};

    res.statusCode = 200;
    return res.end(JSON.stringify({
      operation_mode: userCfg.operation_mode || "FULL",
      auto_send: userCfg.operation_mode === "FULL" || userCfg.operation_mode === "ENTREGA",
      step_timeouts: stepTimeouts,
      mock_balance: gen.mock_balance || "5,420",
      item_name: gen.item_name || "Sword of Destiny",
      item_price: gen.item_price || "1,250",
      post_delivery_delay: gen.post_delivery_delay || 2.0,
      live_proof: userCfg.live_proof || { enabled: true, duration: 4.0, message: "Tô ao vivo rapaziada, não é gravado!" }
    }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
