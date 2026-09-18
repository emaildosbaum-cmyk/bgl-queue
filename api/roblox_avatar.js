// Vercel Serverless Function: Resolve e redireciona para a imagem direta da CDN Roblox (tr.rbxcdn.com)
// Permite que tags <img src="/api/roblox_avatar?userId=..."> renderizem perfeitamente no navegador sem CORS.

const FALLBACK_AVATAR = "https://tr.rbxcdn.com/30day-avatar-headshot/150/150/AvatarHeadshot/Png/regular";
const avatarCache = new Map();

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const urlObj = new URL(req.url, "http://localhost");
  const userId = (urlObj.searchParams.get("userId") || urlObj.searchParams.get("user_id") || "").trim();
  const size = (urlObj.searchParams.get("size") || "150x150").trim();
  const isCircular = urlObj.searchParams.get("circular") !== "false";

  if (!userId || userId === "1" || userId === "0") {
    res.writeHead(302, {
      Location: FALLBACK_AVATAR,
      "Cache-Control": "public, max-age=86400, s-maxage=86400"
    });
    return res.end();
  }

  const cacheKey = `${userId}_${size}_${isCircular}`;
  if (avatarCache.has(cacheKey)) {
    const cachedUrl = avatarCache.get(cacheKey);
    res.writeHead(302, {
      Location: cachedUrl,
      "Cache-Control": "public, max-age=86400, s-maxage=86400, stale-while-revalidate=604800"
    });
    return res.end();
  }

  try {
    const thumbUrl = `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=${encodeURIComponent(userId)}&size=${size}&format=Png&isCircular=${isCircular}`;
    const resp = await fetch(thumbUrl);

    if (resp.ok) {
      const data = await resp.json();
      if (data && Array.isArray(data.data) && data.data.length > 0 && data.data[0].imageUrl) {
        const directUrl = data.data[0].imageUrl;
        avatarCache.set(cacheKey, directUrl);

        res.writeHead(302, {
          Location: directUrl,
          "Cache-Control": "public, max-age=86400, s-maxage=86400, stale-while-revalidate=604800"
        });
        return res.end();
      }
    }
  } catch (err) {
    console.error("[Roblox Avatar] Erro ao resolver thumbnail:", err);
  }

  res.writeHead(302, {
    Location: FALLBACK_AVATAR,
    "Cache-Control": "public, max-age=3600"
  });
  return res.end();
};
