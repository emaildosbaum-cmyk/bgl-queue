// Vercel Serverless Function: Valida se o nick do Roblox é válido e existe no jogo
const https = require('https');

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const urlObj = new URL(req.url, "http://localhost");
  const rawUsername = urlObj.searchParams.get("username") || urlObj.searchParams.get("nick") || "";
  const username = String(rawUsername).trim();

  // 1. Validação de formato estrito: mínimo 6 caracteres, máximo 20, apenas letras, números e underline
  const ROBLOX_NICK_REGEX = /^[a-zA-Z0-9_]{6,20}$/;
  if (!username) {
    res.statusCode = 200;
    return res.end(JSON.stringify({
      valid: false,
      reason: "Por favor, digite um nick."
    }));
  }

  if (username.length < 6) {
    res.statusCode = 200;
    return res.end(JSON.stringify({
      valid: false,
      reason: `O nick deve ter no mínimo 6 caracteres (você digitou ${username.length}).`
    }));
  }

  if (username.length > 20) {
    res.statusCode = 200;
    return res.end(JSON.stringify({
      valid: false,
      reason: `O nick não pode ter mais de 20 caracteres.`
    }));
  }

  if (!ROBLOX_NICK_REGEX.test(username)) {
    res.statusCode = 200;
    return res.end(JSON.stringify({
      valid: false,
      reason: "O nick só pode conter letras (a-z, A-Z), números (0-9) e underline (_)."
    }));
  }

  // 2. Consulta à API oficial de usuários do Roblox
  try {
    const postData = JSON.stringify({
      usernames: [username],
      excludeBannedUsers: true
    });

    const robloxRes = await new Promise((resolve, reject) => {
      const rReq = https.request({
        hostname: "users.roblox.com",
        path: "/v1/usernames/users",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(postData),
          "User-Agent": "BGL-Queue-Validator"
        }
      }, rRes => {
        let raw = "";
        rRes.on("data", c => raw += c);
        rRes.on("end", () => {
          try { resolve(JSON.parse(raw)); } catch(e) { reject(e); }
        });
      });
      rReq.on("error", reject);
      rReq.setTimeout(4500, () => {
        rReq.destroy();
        reject(new Error("Timeout ao consultar API do Roblox"));
      });
      rReq.write(postData);
      rReq.end();
    });

    if (robloxRes && Array.isArray(robloxRes.data) && robloxRes.data.length > 0) {
      const user = robloxRes.data[0];
      return res.end(JSON.stringify({
        valid: true,
        id: user.id,
        name: user.name,
        displayName: user.displayName
      }));
    } else {
      return res.end(JSON.stringify({
        valid: false,
        reason: `O jogador "${username}" não foi encontrado no Roblox. Verifique se digitou o nick correto.`
      }));
    }
  } catch (err) {
    console.error("Roblox API check failed:", err.message);
    // Em caso de falha de rede/timeout com o Roblox, aceita desde que passe no formato estrito
    return res.end(JSON.stringify({
      valid: true,
      fallback: true,
      name: username
    }));
  }
};
