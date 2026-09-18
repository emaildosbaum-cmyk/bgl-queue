// Vercel Serverless Function: Atualiza o passo atual da automação (6 Passos)
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

function parseStepNumber(step, explicitIdx) {
  const exp = parseInt(explicitIdx);
  if (!isNaN(exp) && exp >= 0 && exp <= 6) return exp;
  if (!step) return 0;
  const s = String(step).toLowerCase();
  if (s.includes("abort") || s.includes("cancel") || s.includes("falha") || s.includes("erro")) return -1;
  if (s.includes("recebeu") || s.includes("iniciando compra") || s.includes("passo 1") || s.includes("step 1") || s.includes("verificando loja")) return 1;
  if (s.includes("gift") || s.includes("presente") || s.includes("slot") || (s.includes("clicou") && s.includes("bot")) || s.includes("passo 2") || s.includes("step 2")) return 2;
  if (s.includes("pesquis") || s.includes("digitando") || s.includes("search") || s.includes("passo 3") || s.includes("step 3")) return 3;
  if (s.includes("selecionando") || s.includes("player") || s.includes("jogador") || s.includes("passo 4") || s.includes("step 4")) return 4;
  if (s.includes("purchase") || s.includes("buy") || s.includes("animação de compra") || s.includes("animacao") || s.includes("abriu gui") || s.includes("passo 5") || s.includes("step 5")) return 5;
  if (s.includes("finalizada") || s.includes("conclui") || s.includes("sucesso") || s.includes("fechada") || s.includes("passo 6") || s.includes("step 6")) return 6;
  return 0;
}

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

  let body = {};
  if (req.method === "GET") {
    body.step = urlObj.searchParams.get("step") || "";
  } else if (typeof req.body === "object" && req.body !== null) {
    body = req.body;
  } else if (typeof req.body === "string") {
    try { body = JSON.parse(req.body); } catch(e) {}
  } else {
    const buffers = [];
    for await (const chunk of req) buffers.push(chunk);
    try { body = JSON.parse(Buffer.concat(buffers).toString()); } catch(e) {}
  }
  if (!body.step && urlObj.searchParams.get("step")) {
    body.step = urlObj.searchParams.get("step");
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
    const filter = `or=(script_token.eq.${encodeURIComponent(token)},discord_id.eq.${encodeURIComponent(token)},username.ilike.${encodeURIComponent(token)})`;
    const profileResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?${filter}&select=discord_id`, { headers });
    const profiles = await profileResp.json();
    if (!profiles || profiles.length === 0) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Chave não encontrada no sistema" }));
    }
    const userId = profiles[0].discord_id;

    const rawStepIdx = body.step_index ?? body.current_step ?? urlObj.searchParams.get("step_index") ?? urlObj.searchParams.get("step_num");
    const stepName = body.step || body.step_name || "Em andamento";
    const stepNum = parseStepNumber(stepName, rawStepIdx);

    const isAborted = (stepNum === -1) || body.status === "aborted" || body.status === "error";
    const finalStep = isAborted ? 0 : (stepNum < 0 ? 0 : stepNum);
    const stepStatus = isAborted ? "aborted" : (finalStep === 6 ? "done" : (finalStep === 0 ? "idle" : "in_progress"));

    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        current_step: finalStep,
        step_name: stepName,
        target_nick: body.username || body.nick || body.target_nick || undefined,
        status: stepStatus,
        updated_at: new Date().toISOString()
      })
    });

    res.statusCode = 200;
    return res.end(JSON.stringify({ success: true, step: finalStep, status: stepStatus }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
