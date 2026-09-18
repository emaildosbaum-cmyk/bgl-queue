// Vercel Serverless Function: Retorna dados do usuário autenticado
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

  let user = null;
  const cookieHeader = req.headers.cookie || "";
  const match = cookieHeader.match(/bgl_user_session=([^;]+)/);
  if (match) {
    try {
      const decoded = Buffer.from(match[1], "base64").toString("utf-8");
      user = JSON.parse(decoded);
    } catch (e) {}
  }

  const urlObj = new URL(req.url, "http://localhost");
  const queryToken = urlObj.searchParams.get("token") || (req.headers["authorization"] || "").replace("Bearer ", "").trim();

  const searchId = (user && user.id) || queryToken;
  if (searchId) {
    try {
      const headers = { "apikey": SUPABASE_KEY, "Authorization": `Bearer ${SUPABASE_KEY}` };
      const filter = `or=(discord_id.eq.${encodeURIComponent(searchId)},script_token.eq.${encodeURIComponent(searchId)})`;
      const resp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?${filter}&select=*`, { headers });
      const profiles = await resp.json();
      if (profiles && profiles.length > 0) {
        const p = profiles[0];
        const now = new Date().getTime();
        const robloxPing = p.roblox_last_ping ? new Date(p.roblox_last_ping).getTime() : 0;
        const extPing = p.ext_last_ping ? new Date(p.ext_last_ping).getTime() : 0;

        let robloxAvatar = p.roblox_avatar_url;
        if (!robloxAvatar || robloxAvatar.includes("thumbnails.roblox.com") || robloxAvatar.includes("roproxy.com")) {
          if (p.roblox_user_id) {
            robloxAvatar = `/api/roblox_avatar?userId=${p.roblox_user_id}`;
          } else {
            robloxAvatar = "https://tr.rbxcdn.com/30day-avatar-headshot/150/150/AvatarHeadshot/Png/regular";
          }
        }

        return res.end(JSON.stringify({
          authenticated: true,
          user: {
            id: p.discord_id,
            name: p.username,
            avatar: p.avatar_url || "https://cdn.discordapp.com/embed/avatars/0.png",
            token: p.script_token,
            roblox_user_id: p.roblox_user_id,
            roblox_username: p.roblox_username,
            roblox_display_name: p.roblox_display_name,
            roblox_avatar_url: robloxAvatar,
            roblox_online: (now - robloxPing) < 45000,
            extension_online: (now - extPing) < 45000
          }
        }));
      }
    } catch (err) {}
  }

  if (user) {
    return res.end(JSON.stringify({ authenticated: true, user }));
  }

  res.statusCode = 200;
  return res.end(JSON.stringify({ authenticated: false, user: null }));
};
