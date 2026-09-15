// Vercel Serverless Function: Vincula e trava a conta do Roblox ao token do streamer
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
  let rawToken = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();
  let robloxUserId = urlObj.searchParams.get("roblox_user_id");
  let robloxUsername = urlObj.searchParams.get("roblox_username");
  let robloxDisplayName = urlObj.searchParams.get("roblox_display_name");
  let robloxAvatarUrl = urlObj.searchParams.get("roblox_avatar_url");

  if (req.method === "POST") {
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
    if (body.token) rawToken = body.token;
    if (body.roblox_user_id) robloxUserId = body.roblox_user_id;
    if (body.roblox_username) robloxUsername = body.roblox_username;
    if (body.roblox_display_name) robloxDisplayName = body.roblox_display_name;
    if (body.roblox_avatar_url) robloxAvatarUrl = body.roblox_avatar_url;
  }

  const token = cleanToken(rawToken);
  if (!token) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ error: "Token não fornecido" }));
  }

  if (!robloxUserId && !robloxUsername) {
    res.statusCode = 400;
    return res.end(JSON.stringify({ error: "Dados do Roblox não informados" }));
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json"
  };

  try {
    const filter = `or=(script_token.eq.${encodeURIComponent(token)},discord_id.eq.${encodeURIComponent(token)},username.ilike.${encodeURIComponent(token)})`;
    const profileResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?${filter}&select=*`, { headers });
    const profiles = await profileResp.json();
    if (!profiles || profiles.length === 0) {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Chave não encontrada no sistema" }));
    }

    const profile = profiles[0];
    const nowIso = new Date().toISOString();

    // Se a chave já estiver vinculada a uma conta Roblox
    if (profile.roblox_user_id && String(profile.roblox_user_id).trim() !== "") {
      const linkedId = String(profile.roblox_user_id).trim();
      const currentId = String(robloxUserId || "").trim();

      if (linkedId !== currentId) {
        // Bloqueado! Pertence a outro usuário
        res.statusCode = 403;
        return res.end(JSON.stringify({
          error: `Esta chave está vinculada à conta @${profile.roblox_username || linkedId}. Para usar nesta conta, clique em 'Resetar Chave' no painel do site.`,
          locked: true,
          locked_username: profile.roblox_username || linkedId
        }));
      }

      // Mesmo usuário: atualiza ping e dados se mudaram
      await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(profile.discord_id)}`, {
        method: "PATCH",
        headers,
        body: JSON.stringify({
          roblox_last_ping: nowIso,
          roblox_username: robloxUsername || profile.roblox_username,
          roblox_display_name: robloxDisplayName || profile.roblox_display_name,
          roblox_avatar_url: robloxAvatarUrl || profile.roblox_avatar_url
        })
      });

      res.statusCode = 200;
      return res.end(JSON.stringify({
        ok: true,
        message: "Conta Roblox confirmada com sucesso",
        roblox_username: profile.roblox_username,
        roblox_display_name: profile.roblox_display_name
      }));
    }

    // Primeira vinculação: Trava a chave nesta conta Roblox
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(profile.discord_id)}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({
        roblox_user_id: String(robloxUserId),
        roblox_username: String(robloxUsername || ""),
        roblox_display_name: String(robloxDisplayName || robloxUsername || ""),
        roblox_avatar_url: String(robloxAvatarUrl || `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${robloxUserId}&size=150x150&format=Png&isCircular=true`),
        roblox_last_ping: nowIso
      })
    });

    res.statusCode = 200;
    return res.end(JSON.stringify({
      ok: true,
      message: "Conta Roblox vinculada com sucesso à sua chave",
      roblox_username: robloxUsername,
      roblox_display_name: robloxDisplayName
    }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};