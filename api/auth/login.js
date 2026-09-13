// Vercel Serverless Function: Redireciona para o Discord OAuth2
const CLIENT_ID = process.env.DISCORD_CLIENT_ID || "1548792950480179300";

module.exports = (req, res) => {
  const host = req.headers["x-forwarded-host"] || req.headers.host || "bgl-queue.vercel.app";
  const proto = req.headers["x-forwarded-proto"] || (host.includes("localhost") ? "http" : "https");
  const redirectUri = `${proto}://${host}/api/auth/callback`;

  const discordAuthUrl = `https://discord.com/oauth2/authorize?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${encodeURIComponent(
    redirectUri
  )}&scope=identify%20email`;

  res.writeHead(302, { Location: discordAuthUrl });
  res.end();
};
