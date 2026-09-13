// Vercel Serverless Function: Atualiza o passo atual da automação (6 Passos)
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

function parseStepNumber(step) {
  if (!step) return 0;
  const s = String(step).toLowerCase();
  if (s.includes("1") || s.includes("recebeu")) return 1;
  if (s.includes("2") || s.includes("clicou botão") || s.includes("clicou botao")) return 2;
  if (s.includes("3") || s.includes("pesquisou")) return 3;
  if (s.includes("4") || s.includes("clicou player")) return 4;
  if (s.includes("5") || s.includes("abriu gui")) return 5;
  if (s.includes("6") || s.includes("concluiu")) return 6;
  return 0;
}

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const urlObj = new URL(req.url, "http://localhost");
  const token = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();

  let body = {};
  if (typeof req.body === "object" && req.body !== null) {
    body = req.body;
  } else if (typeof req.body === "string") {
    try { body = JSON.parse(req.body); } catch(e) {}
  } else {
    const buffers = [];
    for await (const chunk of req) buffers.push(chunk);
    try { body = JSON.parse(Buffer.concat(buffers).toString()); } catch(e) {}
  }

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

    const stepName = body.step || body.step_name || "Em andamento";
    const stepNum = parseStepNumber(stepName);

    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        current_step: stepNum,
        step_name: stepName,
        status: stepNum === 6 ? "done" : "in_progress",
        updated_at: new Date().toISOString()
      })
    });

    res.statusCode = 200;
    return res.end(JSON.stringify({ success: true, step: stepNum }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
