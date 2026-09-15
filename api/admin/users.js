// Vercel Serverless Function: Gerenciamento Master de Usuários (Multi-Tenant BGL Queue)
const SUPABASE_URL = process.env.SUPABASE_URL || "https://ojjfwxjirlttpxcjhlho.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU";
const crypto = require("crypto");

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json"
  };

  try {
    // 1. GET: Listar todos os usuários com status e filas
    if (req.method === "GET") {
      const urlObj = new URL(req.url, "http://localhost");
      const targetUserId = urlObj.searchParams.get("user_id");

      // Se for para buscar a fila específica de um usuário
      if (targetUserId && urlObj.searchParams.get("action") === "get_queue") {
        const qResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(targetUserId)}&order=created_at.desc&limit=50`, { headers });
        const queueItems = await qResp.json();
        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, queue: queueItems || [] }));
      }

      // Busca todos os perfis
      const profResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?order=created_at.desc`, { headers });
      const profiles = await profResp.json();

      // Busca filas agrupadas
      const queuesResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?select=id,user_id,status`, { headers });
      const queues = await queuesResp.json();

      const queueCountMap = {};
      const pendingCountMap = {};
      if (Array.isArray(queues)) {
        queues.forEach(q => {
          const uid = q.user_id;
          queueCountMap[uid] = (queueCountMap[uid] || 0) + 1;
          if (q.status === "pending" || q.status === "processing") {
            pendingCountMap[uid] = (pendingCountMap[uid] || 0) + 1;
          }
        });
      }

      const now = Date.now();
      const enrichedProfiles = (Array.isArray(profiles) ? profiles : []).map(p => {
        const robloxPing = p.roblox_last_ping ? new Date(p.roblox_last_ping).getTime() : 0;
        const extPing = p.ext_last_ping ? new Date(p.ext_last_ping).getTime() : 0;

        return {
          ...p,
          roblox_online: (now - robloxPing) < 45000,
          extension_online: (now - extPing) < 45000,
          pending_count: pendingCountMap[p.discord_id] || 0,
          total_queue_count: queueCountMap[p.discord_id] || 0
        };
      });

      res.statusCode = 200;
      return res.end(JSON.stringify({
        ok: true,
        users: enrichedProfiles,
        stats: {
          total_users: enrichedProfiles.length,
          roblox_online_count: enrichedProfiles.filter(u => u.roblox_online).length,
          extension_online_count: enrichedProfiles.filter(u => u.extension_online).length,
          total_pending_queue: Object.values(pendingCountMap).reduce((a, b) => a + b, 0)
        }
      }));
    }

    // 2. POST / PATCH: Ações administrativas
    if (req.method === "POST" || req.method === "PATCH") {
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

      const action = body.action || "";
      const discordId = (body.discord_id || "").trim();

      // AÇÃO: Desvincular Conta Roblox
      if (action === "reset_roblox") {
        if (!discordId) {
          res.statusCode = 400;
          return res.end(JSON.stringify({ error: "discord_id obrigatório" }));
        }

        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(discordId)}`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({
            roblox_user_id: null,
            roblox_username: null,
            roblox_display_name: null,
            roblox_avatar_url: null,
            roblox_last_ping: null
          })
        });

        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, message: "Conta Roblox desvinculada com sucesso! A chave agora está livre." }));
      }

      // AÇÃO: Gerar Novo Script Token
      if (action === "regen_token") {
        if (!discordId) {
          res.statusCode = 400;
          return res.end(JSON.stringify({ error: "discord_id obrigatório" }));
        }

        const newToken = `bgl_${discordId}_${crypto.randomBytes(8).toString("hex")}`;
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(discordId)}`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ script_token: newToken })
        });

        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, script_token: newToken, message: "Nova chave gerada com sucesso!" }));
      }

      // AÇÃO: Criar Novo Usuário Manualmente
      if (action === "create_user") {
        const username = (body.username || "Streamer").trim();
        const customId = (body.discord_id || "").trim() || String(Date.now());
        const newToken = `bgl_${customId}_${crypto.randomBytes(8).toString("hex")}`;
        const avatarUrl = body.avatar_url || `https://cdn.discordapp.com/embed/avatars/${Math.floor(Math.random() * 5)}.png`;

        const newProfile = {
          discord_id: customId,
          username: username,
          avatar_url: avatarUrl,
          script_token: newToken,
          created_at: new Date().toISOString(),
          last_seen: new Date().toISOString(),
          roblox_user_id: null,
          roblox_username: null,
          roblox_display_name: null,
          roblox_avatar_url: null
        };

        const insResp = await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles`, {
          method: "POST",
          headers,
          body: JSON.stringify(newProfile)
        });

        if (!insResp.ok) {
          const errTxt = await insResp.text();
          res.statusCode = 500;
          return res.end(JSON.stringify({ error: "Erro ao criar usuário: " + errTxt }));
        }

        // Cria configs padrão
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs`, {
          method: "POST",
          headers,
          body: JSON.stringify({
            discord_id: customId,
            operation_mode: "FULL",
            queue_paused: false,
            tts_enabled: true
          })
        });

        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, user: newProfile, message: "Usuário criado com sucesso!" }));
      }

      // AÇÃO: Limpar Fila do Usuário
      if (action === "clear_queue") {
        if (!discordId) {
          res.statusCode = 400;
          return res.end(JSON.stringify({ error: "discord_id obrigatório" }));
        }

        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(discordId)}`, {
          method: "DELETE",
          headers
        });

        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, message: "Fila do usuário limpa com sucesso!" }));
      }

      // AÇÃO: Excluir Usuário
      if (action === "delete_user") {
        if (!discordId) {
          res.statusCode = 400;
          return res.end(JSON.stringify({ error: "discord_id obrigatório" }));
        }

        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_queues?user_id=eq.${encodeURIComponent(discordId)}`, { method: "DELETE", headers });
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_configs?discord_id=eq.${encodeURIComponent(discordId)}`, { method: "DELETE", headers });
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_steps?user_id=eq.${encodeURIComponent(discordId)}`, { method: "DELETE", headers });
        await fetch(`${SUPABASE_URL}/rest/v1/bgl_user_profiles?discord_id=eq.${encodeURIComponent(discordId)}`, { method: "DELETE", headers });

        res.statusCode = 200;
        return res.end(JSON.stringify({ ok: true, message: "Usuário e dados excluídos com sucesso!" }));
      }

      // Ação não reconhecida
      res.statusCode = 400;
      return res.end(JSON.stringify({ error: "Ação não reconhecida" }));
    }

    res.statusCode = 405;
    return res.end(JSON.stringify({ error: "Método não permitido" }));
  } catch (err) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ error: err.message }));
  }
};
