// Vercel Serverless Function: Processa o retorno do Discord OAuth2
const crypto = require("crypto");

const CLIENT_ID = process.env.DISCORD_CLIENT_ID || "1548792950480179300";
const CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || "txHLdDCkPY5VQZxSrIzQLejnggGseZ1m";
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";

module.exports = async (req, res) => {
  const urlObj = new URL(req.url, "http://localhost");
  const code = urlObj.searchParams.get("code");
  const error = urlObj.searchParams.get("error");

  if (error || !code) {
    res.writeHead(302, { Location: `/?auth_error=${encodeURIComponent(error || "no_code")}` });
    return res.end();
  }

  const host = req.headers["x-forwarded-host"] || req.headers.host || "bgl-queue.vercel.app";
  const proto = req.headers["x-forwarded-proto"] || (host.includes("localhost") ? "http" : "https");
  const redirectUri = `${proto}://${host}/api/auth/callback`;

  try {
    // 1. Troca o código pelo access_token no Discord
    const tokenParams = new URLSearchParams({
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirectUri
    });

    const tokenResp = await fetch("https://discord.com/api/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenParams.toString()
    });

    if (!tokenResp.ok) {
      const errText = await tokenResp.text();
      console.error("Erro Discord Token:", errText);
      res.writeHead(302, { Location: `/?auth_error=token_exchange_failed` });
      return res.end();
    }

    const tokenData = await tokenResp.json();
    const accessToken = tokenData.access_token;

    // 2. Obtém perfil do usuário no Discord
    const userResp = await fetch("https://discord.com/api/users/@me", {
      headers: { Authorization: `Bearer ${accessToken}` }
    });

    if (!userResp.ok) {
      res.writeHead(302, { Location: `/?auth_error=profile_fetch_failed` });
      return res.end();
    }

    const discordUser = await userResp.json();
    const discordId = discordUser.id;
    const displayName = discordUser.global_name || discordUser.username || "Player";
    const avatarUrl = discordUser.avatar
      ? `https://cdn.discordapp.com/avatars/${discordId}/${discordUser.avatar}.png?size=128`
      : `https://cdn.discordapp.com/embed/avatars/${(parseInt(discordId) >> 22) % 6}.png`;

    // 3. Gera um script_token estável e único para o Roblox deste usuário
    const hash = crypto.createHmac("sha256", CLIENT_SECRET).update(discordId).digest("hex").slice(0, 16);
    const scriptToken = `bgl_${discordId}_${hash}`;

    // 4. Salva ou atualiza no Supabase (Multi-tenant)
    const headersSupabase = {
      "apikey": SUPABASE_KEY,
      "Authorization": `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
      "Prefer": "resolution=merge-duplicates,return=minimal"
    };

    // Upsert Perfil
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles`, {
      method: "POST",
      headers: headersSupabase,
      body: JSON.stringify({
        discord_id: discordId,
        username: displayName,
        avatar_url: avatarUrl,
        script_token: scriptToken,
        last_seen: new Date().toISOString()
      })
    });

    // Garante Configuração Padrão do Usuário
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs`, {
      method: "POST",
      headers: headersSupabase,
      body: JSON.stringify({
        discord_id: discordId,
        operation_mode: "FULL",
        queue_paused: false,
        tiktok_username: "",
        tiktok_connected: false,
        thank_nicks_enabled: true
      })
    });

    // Garante Registro de Passos
    await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps`, {
      method: "POST",
      headers: headersSupabase,
      body: JSON.stringify({
        user_id: discordId,
        current_step: 0,
        step_name: "Aguardando fila...",
        status: "idle"
      })
    });

    // 5. Redireciona de volta para o Dashboard com os dados da sessão
    const sessionData = {
      discord_id: discordId,
      username: displayName,
      avatar_url: avatarUrl,
      script_token: scriptToken,
      ts: Date.now()
    };
    const sessionCookieVal = Buffer.from(JSON.stringify(sessionData)).toString("base64");

    res.writeHead(302, {
      "Set-Cookie": `bgl_user_session=${sessionCookieVal}; Path=/; Max-Age=2592000; SameSite=Lax`,
      Location: `/?auth=success&uid=${discordId}&name=${encodeURIComponent(displayName)}&avatar=${encodeURIComponent(avatarUrl)}&token=${scriptToken}`
    });
    return res.end();
  } catch (err) {
    console.error("Erro no callback Discord:", err);
    res.writeHead(302, { Location: `/?auth_error=internal_error` });
    return res.end();
  }
};
