// Vercel Serverless Function: Finaliza entrega ou registra cancelamento
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
    body.status = urlObj.searchParams.get("status") || "success";
    body.error = urlObj.searchParams.get("error") || "";
    body.reason = urlObj.searchParams.get("reason") || "";
  } else if (typeof req.body === "object" && req.body !== null) {
    body = req.body;
  } else if (typeof req.body === "string") {
    try { body = JSON.parse(req.body); } catch(e) {}
  } else {
    const buffers = [];
    for await (const chunk of req) buffers.push(chunk);
    try { body = JSON.parse(Buffer.concat(buffers).toString()); } catch(e) {}
  }
  if (!body.status && urlObj.searchParams.get("status")) {
    body.status = urlObj.searchParams.get("status");
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

    const status = body.status || "delivered";
    const username = body.username || body.nick || "";

    if (status === "delivered") {
      // 1. Salva nas entregas do usuário
      await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_deliveries`, {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({
          user_id: userId,
          username: username,
          nick: username,
          amount: Number(body.amount) || 1,
          delivered_at: new Date().toISOString()
        })
      });

      // 2. Atualiza item na fila deste usuário
      if (username) {
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(userId)}&nick=eq.${encodeURIComponent(username)}&status=eq.processing`, {
          method: "PATCH",
          headers: { ...headers, "Content-Type": "application/json" },
          body: JSON.stringify({ status: "delivered" })
        });
      }

      // 3. Atualiza stepper para concluído
      await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(userId)}`, {
        method: "PATCH",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({
          current_step: 6,
          step_name: "Concluiu",
          status: "done",
          updated_at: new Date().toISOString()
        })
      });
    } else {
      // Abortado / cancelado
      if (username) {
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(userId)}&nick=eq.${encodeURIComponent(username)}&status=eq.processing`, {
          method: "PATCH",
          headers: { ...headers, "Content-Type": "application/json" },
          body: JSON.stringify({ status: "cancelled" })
        });
      }
      await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(userId)}`, {
        method: "PATCH",
        headers: { ...headers, "Content-Type": "application/json" },
        body: JSON.stringify({
          current_step: 0,
          step_name: "Aguardando fila...",
          target_nick: "",
          status: "idle",
          updated_at: new Date().toISOString()
        })
      });
    }

    res.statusCode = 200;
    return res.end(JSON.stringify({ success: true }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
