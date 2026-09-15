// Vercel Serverless Function: Desvincula a conta do Roblox e gera uma nova chave segura
const crypto = require("crypto");

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
  }

  const token = cleanToken(rawToken);
  if (!token) {
    res.statusCode = 401;
    return res.end(JSON.stringify({ error: "Token não fornecido" }));
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
    const newToken = `bgl_${profile.discord_id}_${crypto.randomBytes(8).toString("hex")}`;

    // Desvincula conta Roblox e gera nova chave
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(profile.discord_id)}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({
        script_token: newToken,
        roblox_user_id: null,
        roblox_username: null,
        roblox_display_name: null,
        roblox_avatar_url: null,
        roblox_last_ping: null
      })
    });

    res.statusCode = 200;
    return res.end(JSON.stringify({
      ok: true,
      message: "Chave resetada e conta Roblox desvinculada com sucesso!",
      new_token: newToken
    }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};