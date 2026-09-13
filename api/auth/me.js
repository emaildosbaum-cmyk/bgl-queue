// Vercel Serverless Function: Retorna dados do usuário autenticado
module.exports = (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    return res.end();
  }

  const cookieHeader = req.headers.cookie || "";
  const match = cookieHeader.match(/bgl_user_session=([^;]+)/);
  if (match) {
    try {
      const decoded = Buffer.from(match[1], "base64").toString("utf-8");
      const user = JSON.parse(decoded);
      return res.end(JSON.stringify({ authenticated: true, user }));
    } catch (e) {
      // cookie inválido
    }
  }

  res.statusCode = 200;
  res.end(JSON.stringify({ authenticated: false, user: null }));
};
