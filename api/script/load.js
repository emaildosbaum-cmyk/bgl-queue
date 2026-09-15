// Vercel Serverless Function: Retorna o bootstrap Luau do Loader de 1 Linha
module.exports = async (req, res) => {
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Access-Control-Allow-Origin", "*");

  const urlObj = new URL(req.url, "http://localhost");
  const token = (urlObj.searchParams.get("token") || "").trim().replace(/^["']|["']$/g, "").trim();

  const luaCode = `-- [BGL Queue] Loader de 1 Linha Oficial
-- Gerado automaticamente para o seu perfil
${token ? `_G.BGL_TOKEN = "${token}"` : `-- Nenhum token passado no link, lendo de bgl_token.txt se existir`}

local ok, code = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/emaildosbaum-cmyk/bgl-queue/main/safe.lua?t=" .. tostring(os.time()))
end)

if ok and code and code ~= "" then
    local fn, err = loadstring(code)
    if fn then
        fn()
    else
        warn("[BGL Queue] Erro ao compilar safe.lua: " .. tostring(err))
    end
else
    local fallbackOk, fallbackCode = pcall(function()
        return game:HttpGet("https://bgl-queue.vercel.app/safe.lua?t=" .. tostring(os.time()))
    end)
    if fallbackOk and fallbackCode and fallbackCode ~= "" then
        local fn, err = loadstring(fallbackCode)
        if fn then
            fn()
        else
            warn("[BGL Queue] Erro ao compilar fallback: " .. tostring(err))
        end
    else
        warn("[BGL Queue] Erro ao carregar script da nuvem. Verifique sua conexão.")
    end
end
`;

  res.statusCode = 200;
  return res.end(luaCode);
};