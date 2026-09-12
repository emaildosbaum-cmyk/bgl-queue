"""
BGL Queue — le o chat da sua live no TikTok, filtra os nicks que a galera manda
e mantem uma fila ao vivo pra voce ir confirmando os robux manualmente.

Uso basico:
    pip install TikTokLive websockets --break-system-packages
    python3 server.py @seu_usuario_tiktok

Uso com opcoes:
    python3 server.py @seu_usuario_tiktok --cooldown 180 --ws-port 8765 --http-port 8080

Depois abra queue.html no navegador (duplo clique nele) — ele conecta
sozinho no servidor local e mostra a fila em tempo real.
"""

import argparse
import asyncio
import http.server
import json
import logging
import os
import re
import secrets
import socketserver
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error
import urllib.parse
from collections import deque
from http.cookies import SimpleCookie
from pathlib import Path

try:
    import keyboard
    _KEYBOARD_OK = True
except ImportError:
    _KEYBOARD_OK = False

import websockets
from TikTokLive import TikTokLiveClient
from TikTokLive.client.web.web_settings import WebDefaults
from TikTokLive.events import CommentEvent, ConnectEvent, DisconnectEvent

# ---------------------------------------------------------------------------
# Logging — com horario, pra facilitar debug de live longa
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("bgl_queue")


# ---------------------------------------------------------------------------
# Utilitarios Mobile PWA — deteccao de IP e QR Code no terminal
# ---------------------------------------------------------------------------
def get_local_ip() -> str:
    """Retorna o IP local na rede Wi-Fi/LAN (nao o loopback 127.0.0.1)."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def print_mobile_url(url: str):
    """Exibe a URL do app mobile no terminal e tenta gerar um QR Code ASCII."""
    sep = "=" * 60
    try:
        import qrcode  # type: ignore
        import io, sys
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.make(fit=True)
        # Captura o QR Code em string para evitar problemas de encoding do terminal
        buf = io.StringIO()
        qr.print_ascii(out=buf, invert=True)
        qr_text = buf.getvalue()
        print(sep)
        print("  ACESSE O APP MOBILE NO CELULAR:")
        print(f"  {url}")
        print("  Escaneie o QR Code abaixo:")
        print(sep)
        try:
            print(qr_text)
        except UnicodeEncodeError:
            # Terminal Windows sem suporte a Unicode — exibe so a URL
            print("  (QR Code nao suportado neste terminal)")
            print(f"  >>> {url} <<<")
        print(sep)
        sys.stdout.flush()
    except ImportError:
        print(sep)
        print("  ACESSE O APP MOBILE NO CELULAR:")
        print(f"  >>> {url} <<<")
        print("  Dica: instale 'qrcode': pip install qrcode")
        print(sep)

def configurar_bloqueio_protocolo():
    """Configura o bloqueio automático de protocolos do Roblox no Registro do Windows para o Chrome."""
    if os.name != 'nt':
        return
    try:
        import winreg
        key_path = r"SOFTWARE\Policies\Google\Chrome\URLBlocklist"
        key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path)
        winreg.SetValueEx(key, "1", 0, winreg.REG_SZ, "roblox-player:*")
        winreg.SetValueEx(key, "2", 0, winreg.REG_SZ, "roblox:*")
        winreg.SetValueEx(key, "3", 0, winreg.REG_SZ, "fishstrap:*")
        winreg.CloseKey(key)
        log.info("Bloqueio de protocolos roblox://, roblox-player:// e fishstrap:// configurado no Registro do Windows!")
    except Exception as e:
        log.warning(f"Não foi possível configurar o bloqueio de protocolo no Registro: {e}")

# Executa o bloqueio ao iniciar
configurar_bloqueio_protocolo()

def _ensure_background_asset():
    """Garante que a imagem de fundo do Roblox esteja presente em icons/roblox_bg.jpg."""
    target = Path(__file__).resolve().parent / "icons" / "roblox_bg.jpg"
    if not target.exists():
        possible_sources = [
            Path(r"C:\Users\jvtri\.gemini\antigravity\brain\fed728a1-216c-4624-93eb-9ca0c33c179a\roblox_gaming_bg_1789141716045.jpg"),
        ]
        import shutil
        for src in possible_sources:
            if src.exists():
                try:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(str(src), str(target))
                    log.info(f"Asset icons/roblox_bg.jpg copiado com sucesso a partir de {src}")
                    break
                except Exception as e:
                    log.warning(f"Não foi possível copiar asset roblox_bg.jpg: {e}")

_ensure_background_asset()

# Regra de username do Roblox: 3-20 caracteres, letras/numeros/underscore,
# nao pode comecar/terminar com underscore nem ter underscore duplo.
ROBLOX_USERNAME_RE = re.compile(r'^(?!_)(?!.*__)[A-Za-z0-9_]{3,20}(?<!_)$')

# URL da API do Roblox para verificar se um username existe
ROBLOX_USERS_API = "https://users.roblox.com/v1/usernames/users"

# Cache de resultados da API: username_lower -> (existe: bool, timestamp: float)
_roblox_cache: dict = {}
CACHE_TTL = 600  # 10 minutos

# Cole sua API key da Euler Stream aqui (https://www.eulerstream.com/dashboard)
# pra nao precisar passar --api-key toda vez que rodar. Deixa "" se quiser
# continuar passando pela linha de comando.
EULER_API_KEY = "euler_ZGFiNmNkMjc5NDg1Zjk2ZDg4MDk2ZTY4N2M2YTcxZjhmNzEwNjQyNThmMWJhNTkxMGM1Yzg2"

# Webhook do Discord — enviado automaticamente quando a live terminar
DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1536385795684831373/Dm3YMoL_z_0qM0hcyP3jV188loahavFn5o3ffJzOHfYrXoC4nzmAoBvSf23QHVsvIxjX"

PERSIST_FILE = Path("queue_state.json")
BANNED_FILE  = Path("banned_nicks.json")
SPEECH_FILE  = Path("speech_variations.json")

# Supabase Cloud Integration
SUPABASE_URL = "https://ojjfwxjirlttpxcjhlho.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qamZ3eGppcmx0dHB4Y2pobGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjExMjcsImV4cCI6MjEwNDc5NzEyN30.QiBcBHLwS2yWbmgi_oAKSmRU1UEFNRXgfyLujmEK7XU"

def _supabase_sync_worker(method: str, path: str, data=None):
    try:
        url = f"{SUPABASE_URL}/rest/v1/{path}"
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal"
        }
        body = json.dumps(data).encode("utf-8") if data is not None else None
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=5) as resp:
            pass
    except Exception as e:
        log.debug(f"[Supabase] sync notice: {e}")

async def supabase_sync(method: str, path: str, data=None):
    try:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, _supabase_sync_worker, method, path, data)
    except Exception:
        pass

# ---------------------------------------------------------------------------
# Autenticação e Gestão de Sessões
# ---------------------------------------------------------------------------
AUTH_PASSWORD = "joaolegal"
SESSION_COOKIE_NAME = "bgl_session"
SESSION_MAX_AGE = 86400 * 7  # 7 dias (604800 segundos)
SESSIONS_FILE = Path(__file__).resolve().parent / "sessions.json"


class SessionManager:
    """Gerenciador thread-safe de sessões autenticadas com persistência em JSON e expiração."""

    def __init__(self, persist_file: Path = SESSIONS_FILE):
        self.persist_file = Path(persist_file)
        self.lock = threading.RLock()
        self.sessions: dict[str, float] = {}  # token -> expires_at (unix timestamp)
        self.load()

    def load(self):
        with self.lock:
            if not self.persist_file.exists():
                self.sessions = {}
                return
            try:
                raw = self.persist_file.read_text(encoding="utf-8")
                data = json.loads(raw)
                now = time.time()
                self.sessions = {}
                if isinstance(data, dict):
                    for token, val in data.items():
                        exp = None
                        if isinstance(val, (int, float)):
                            exp = float(val)
                        elif isinstance(val, dict):
                            raw_exp = (
                                val.get("expires_at")
                                or val.get("expires")
                                or val.get("exp")
                                or val.get("ts")
                            )
                            if isinstance(raw_exp, (int, float)):
                                exp = float(raw_exp)
                        if exp is not None and exp > now:
                            self.sessions[str(token)] = exp
            except Exception as e:
                log.warning(f"Erro ao carregar sessões de {self.persist_file}: {e}")
                self.sessions = {}

    def save(self):
        with self.lock:
            try:
                now = time.time()
                self.sessions = {t: exp for t, exp in self.sessions.items() if exp > now}
                serialized = {
                    t: {"expires_at": exp}
                    for t, exp in self.sessions.items()
                }
                self.persist_file.write_text(
                    json.dumps(serialized, indent=2),
                    encoding="utf-8"
                )
            except Exception as e:
                log.warning(f"Erro ao salvar sessões em {self.persist_file}: {e}")

    def create_session(self) -> str:
        token = secrets.token_urlsafe(32)
        expires_at = time.time() + SESSION_MAX_AGE
        with self.lock:
            self.sessions[token] = expires_at
            self.save()
        return token

    def is_valid(self, token: str | None) -> bool:
        if not token:
            return False
        with self.lock:
            expires_at = self.sessions.get(token)
            if expires_at is None:
                return False
            if expires_at > time.time():
                return True
            # Token expirado: remove e persiste
            del self.sessions[token]
            self.save()
            return False

    def invalidate(self, token: str | None):
        if not token:
            return
        with self.lock:
            if token in self.sessions:
                del self.sessions[token]
                self.save()


session_manager = SessionManager()


class AuthHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Handler HTTP com autenticação de sessão via cookie, proteção de rotas e bloqueio de arquivos sensíveis."""

    PROTECTED_FILES = {"queue.html", "mobile.html"}
    BLOCKED_EXTENSIONS = {".py", ".bat", ".ps1", ".reg", ".lua"}
    BLOCKED_FILES = {
        "sessions.json",
        "queue_state.json",
        "banned_nicks.json",
        "speech_variations.json",
        "ultimo_perfil.txt",
    }

    def _get_cookie(self, name: str) -> str | None:
        cookie_header = self.headers.get("Cookie")
        if not cookie_header:
            return None
        try:
            cookie = SimpleCookie()
            cookie.load(cookie_header)
            if name in cookie:
                return cookie[name].value
        except Exception:
            return None
        return None

    def _is_authenticated(self) -> bool:
        token = self._get_cookie(SESSION_COOKIE_NAME)
        return session_manager.is_valid(token) if token else False

    def _send_redirect(self, location: str, cookie_header: str | None = None):
        self.send_response(303)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        if cookie_header:
            self.send_header("Set-Cookie", cookie_header)
        self.end_headers()

    def _send_json(self, status: int, data: dict, cookie_header: str | None = None):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        if cookie_header:
            self.send_header("Set-Cookie", cookie_header)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _handle_api_login_method_not_allowed(self) -> bool:
        parsed = urllib.parse.urlsplit(self.path)
        clean_path = urllib.parse.unquote(parsed.path).rstrip("/")
        norm_path = os.path.normpath(clean_path).replace("\\", "/").lower()
        sanitized_path = norm_path.split("::")[0].split(":")[0].rstrip(". ")
        if clean_path in ("/api/login",) or sanitized_path in ("/api/login",):
            body = json.dumps({"success": False, "error": "Método não permitido."}, ensure_ascii=False).encode("utf-8")
            self.send_response(405)
            self.send_header("Allow", "POST")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            return True
        return False

    def do_OPTIONS(self):
        if self._handle_api_login_method_not_allowed():
            return
        self.send_error(501, f"Unsupported method ({self.command})")

    def do_PUT(self):
        if self._handle_api_login_method_not_allowed():
            return
        self.send_error(501, f"Unsupported method ({self.command})")

    def do_DELETE(self):
        if self._handle_api_login_method_not_allowed():
            return
        self.send_error(501, f"Unsupported method ({self.command})")

    def _handle_get_or_head(self, is_head: bool = False):
        parsed = urllib.parse.urlsplit(self.path)
        clean_path = urllib.parse.unquote(parsed.path).replace("\\", "/")
        norm_path = os.path.normpath(clean_path).replace("\\", "/").lower()
        # Normalização NTFS: remove Alternate Data Streams e trailing dots/spaces
        sanitized_path = norm_path.split("::")[0].split(":")[0].rstrip(". ")
        filename = os.path.basename(sanitized_path).lower()
        ext = os.path.splitext(filename)[1].lower()

        # 0. Método não permitido para /api/login em GET / HEAD (HTTP 405)
        if self._handle_api_login_method_not_allowed():
            return

        # 1. Rota raiz: redireciona para /queue.html (que exige login se não autenticado)
        if clean_path in ("", "/") or sanitized_path in ("", "/"):
            self._send_redirect("/queue.html")
            return

        # 2. Rota de logout
        if clean_path in ("/logout", "/api/logout") or sanitized_path in ("/logout", "/api/logout"):
            token = self._get_cookie(SESSION_COOKIE_NAME)
            if token:
                session_manager.invalidate(token)
            cookie_header = (
                f"{SESSION_COOKIE_NAME}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; "
                f"Max-Age=0; HttpOnly; SameSite=Lax"
            )
            self._send_redirect("/login", cookie_header)
            return

        # 3. Rota de login
        if clean_path in ("/login", "/login.html") or sanitized_path in ("/login", "/login.html"):
            if self._is_authenticated():
                self._send_redirect("/queue.html")
                return
            login_file = Path(__file__).resolve().parent / "login.html"
            if login_file.exists():
                self.path = "/login.html"
                if is_head:
                    return super().do_HEAD()
                return super().do_GET()
            else:
                self._serve_fallback_login(is_head=is_head)
                return

        # 4. Bloqueia acesso a arquivos de código, scripts e dados sensíveis (HTTP 403)
        if (
            filename in self.BLOCKED_FILES
            or ext in self.BLOCKED_EXTENSIONS
            or sanitized_path.startswith("/.agents")
            or sanitized_path.startswith(".agents")
            or "/.agents" in sanitized_path
            or sanitized_path.startswith("/.git")
            or sanitized_path.startswith("/tests")
        ):
            self.send_error(403, "Acesso proibido.")
            return

        # 5. Rotas protegidas (queue.html e mobile.html, incluindo nomes curtos NTFS como QUEUE~1.HTM)
        is_protected = (
            filename in self.PROTECTED_FILES
            or filename.startswith("queue~")
            or filename.startswith("mobile~")
            or (("queue" in filename or "mobile" in filename) and "~" in filename)
        )
        if is_protected:
            if not self._is_authenticated():
                target = f"/{filename}"
                if parsed.query:
                    target += f"?{parsed.query}"
                self._send_redirect(f"/login?redirect={urllib.parse.quote(target, safe='')}")
                return

        # 6. Demais rotas públicas (overlay.html, manifest_mobile.json, sw.js, icons, css, js)
        if is_head:
            return super().do_HEAD()
        return super().do_GET()

    def do_GET(self):
        self._handle_get_or_head(is_head=False)

    def do_HEAD(self):
        self._handle_get_or_head(is_head=True)

    def do_POST(self):
        parsed = urllib.parse.urlsplit(self.path)
        clean_path = urllib.parse.unquote(parsed.path).rstrip("/")
        norm_path = os.path.normpath(clean_path).replace("\\", "/").lower()
        sanitized_path = norm_path.split("::")[0].split(":")[0].rstrip(". ")

        if clean_path in ("/login", "/api/login") or sanitized_path in ("/login", "/api/login"):
            content_length = int(self.headers.get("Content-Length", 0))
            raw_body = self.rfile.read(content_length).decode("utf-8", errors="replace")
            content_type = self.headers.get("Content-Type", "")

            password = ""
            redirect_to = "/queue.html"
            is_json = ("application/json" in content_type) or (clean_path == "/api/login") or (sanitized_path == "/api/login")

            if is_json:
                try:
                    payload = json.loads(raw_body)
                    if not isinstance(payload, dict):
                        self._send_json(400, {"success": False, "error": "JSON deve ser um objeto"})
                        return
                    raw_pwd = payload.get("password")
                    password = str(raw_pwd) if raw_pwd is not None else ""
                    redirect_to = str(payload.get("redirect", redirect_to))
                except Exception:
                    self._send_json(400, {"success": False, "error": "JSON inválido"})
                    return
            else:
                form_data = urllib.parse.parse_qs(raw_body)
                password = form_data.get("password", [""])[0]
                redirect_to = form_data.get("redirect", [redirect_to])[0]

            # Proteção contra open-redirect (unquote recursivo contra bypass de double-encoding)
            decoded = redirect_to
            for _ in range(5):
                next_dec = urllib.parse.unquote(decoded).strip()
                if next_dec == decoded:
                    break
                decoded = next_dec
            decoded = decoded.replace("\\", "/").strip()
            if not decoded.startswith("/") or decoded.startswith("//") or "://" in decoded:
                redirect_to = "/queue.html"
            else:
                redirect_to = decoded

            pwd_bytes = str(password).encode("utf-8", errors="replace")
            auth_bytes = AUTH_PASSWORD.encode("utf-8")
            if secrets.compare_digest(pwd_bytes, auth_bytes):
                token = session_manager.create_session()
                # NOTA: Não definir flag Secure para evitar rejeição em HTTP local/LAN
                cookie_header = (
                    f"{SESSION_COOKIE_NAME}={token}; Path=/; HttpOnly; "
                    f"SameSite=Lax; Max-Age={SESSION_MAX_AGE}"
                )
                if is_json:
                    self._send_json(200, {"success": True, "redirect": redirect_to}, cookie_header)
                else:
                    self._send_redirect(redirect_to, cookie_header)
            else:
                if is_json:
                    self._send_json(401, {"success": False, "error": "Senha incorreta"})
                else:
                    self._send_redirect(f"/login?error=1&redirect={urllib.parse.quote(redirect_to, safe='')}")
            return

        if clean_path in ("/logout", "/api/logout") or sanitized_path in ("/logout", "/api/logout"):
            token = self._get_cookie(SESSION_COOKIE_NAME)
            if token:
                session_manager.invalidate(token)
            cookie_header = (
                f"{SESSION_COOKIE_NAME}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; "
                f"Max-Age=0; HttpOnly; SameSite=Lax"
            )
            if "application/json" in self.headers.get("Content-Type", "") or clean_path == "/api/logout" or sanitized_path == "/api/logout":
                self._send_json(200, {"success": True}, cookie_header)
            else:
                self._send_redirect("/login", cookie_header)
            return

        self.send_error(404, "Endpoint não encontrado.")

    def _serve_fallback_login(self, is_head: bool = False):
        """Página HTML de login Glassmorphism autônoma embutida caso login.html não esteja no disco."""
        html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BGL Queue — Login</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #090a10 radial-gradient(circle at 50% 30%, #1e1b4b 0%, #090a10 70%);
      color: #f4f4f5;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }}
    .glass-card {{
      background: rgba(14, 17, 28, 0.75);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 20px;
      padding: 36px 32px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6);
      text-align: center;
    }}
    h1 {{ font-size: 24px; font-weight: 800; margin-bottom: 6px; }}
    p {{ font-size: 13px; color: #9ca3af; margin-bottom: 24px; }}
    .error-msg {{
      background: rgba(239, 68, 68, 0.2);
      border: 1px solid rgba(239, 68, 68, 0.4);
      color: #fca5a5;
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 13px;
      margin-bottom: 18px;
    }}
    .form-group {{ margin-bottom: 20px; text-align: left; }}
    label {{ display: block; font-size: 12px; font-weight: 600; margin-bottom: 8px; color: #cbd5e1; }}
    input[type="password"] {{
      width: 100%;
      background: rgba(10, 12, 18, 0.65);
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-radius: 12px;
      padding: 13px 16px;
      font-size: 14px;
      color: #fff;
      outline: none;
    }}
    button {{
      width: 100%;
      background: linear-gradient(135deg, #06b6d4, #2563eb);
      border: none;
      border-radius: 12px;
      padding: 14px;
      font-size: 15px;
      font-weight: 700;
      color: #fff;
      cursor: pointer;
    }}
  </style>
</head>
<body>
  <div class="glass-card">
    <h1>BGL Queue</h1>
    <p>Acesso restrito ao painel de controle</p>
    <div id="errorBanner" class="error-msg" style="display: none;">Senha incorreta. Tente novamente.</div>
    <form id="loginForm" method="POST" action="/login">
      <input type="hidden" name="redirect" id="redirectInput" value="/queue.html">
      <div class="form-group">
        <label for="password">Senha de Acesso</label>
        <input type="password" id="password" name="password" placeholder="Digite a senha..." required autofocus>
      </div>
      <button type="submit">Entrar no Painel</button>
    </form>
  </div>
  <script>
    const params = new URLSearchParams(window.location.search);
    if (params.get('error')) document.getElementById('errorBanner').style.display = 'block';
    if (params.get('redirect')) document.getElementById('redirectInput').value = params.get('redirect');
  </script>
</body>
</html>"""
        encoded = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.end_headers()
        if not is_head:
            self.wfile.write(encoded)


class QueueServer:
    def __init__(self, args):
        self.args = args
        # configs que podem ser mudadas em tempo real pelo painel do queue.html
        # (comecam com o valor passado por linha de comando, mas dá pra
        # sobrescrever depois sem reiniciar o servidor)
        self.settings = {
            "cooldown": args.cooldown,
            "max_queue": args.max_queue,
            "pickup_delay": args.pickup_delay,
            "operation_mode": "FULL",
            "auto_send": True,
        }
        self.queue = deque()            # itens: {"id": int, "nick": str, "sender": str, "ts": float}
        self.last_seen = {}             # tiktok_user_id -> timestamp da ultima entrada aceita
        self.connected_clients = set()  # websockets conectados no frontend
        self.next_id = 1
        self.total_received = 0
        self.total_entregas = 0
        self.total_rejected_duplicate = 0
        self.total_rejected_cooldown = 0
        self.live_start_time = None     # registra quando a live comecou
        self.tiktok_connected = False   # se o client do TikTok esta conectado na live
        self.tiktok_connecting = False
        perfil_salvo = ""
        try:
            p_file = Path("ultimo_perfil.txt")
            if p_file.exists():
                perfil_salvo = p_file.read_text(encoding="utf-8").strip().lstrip("@")
        except Exception:
            pass
        self.tiktok_username = (getattr(args, "username", "") or perfil_salvo).lstrip("@").strip()
        self.tiktok_task = None
        self.tiktok_client = None

        # --- Banimento permanente ---
        self.banned_nicks: set = set()   # nicks banidos permanentemente (nunca entram na fila)

        # --- Automacao de Live ---
        self.auto_settings = {
            "live_duration_minutes": 30,
            "pause_between_lives_minutes": 5,
            "wait_after_open_seconds": 8,
            "live_url": "https://www.roblox.com/upgrades/robux?ctx=navpopover",
            "repeat_times": 0,  # 0 = infinito
            "chrome_path": r"C:\Program Files\Google\Chrome\Application\chrome.exe",
            "close_message": "Atenção, a live vai encerrar em 10 segundos.",
        }
        self.auto_live_state = "idle"   # idle | live | paused
        self.auto_live_task = None
        self.live_cycle = 0
        self.live_phase_end_time = 0.0  # timestamp unix de quando a fase atual termina

        self.load_state()
        self.load_banned()

    # -----------------------------------------------------------------
    # Persistencia em disco — se o script cair/reiniciar, a fila nao some
    # -----------------------------------------------------------------
    def load_state(self):
        if not PERSIST_FILE.exists():
            return
        try:
            data = json.loads(PERSIST_FILE.read_text(encoding="utf-8"))
            self.queue = deque(data.get("queue", []))
            self.next_id = data.get("next_id", 1)
            
            if "settings" in data:
                self.settings.update(data["settings"])
            if "auto_settings" in data:
                self.auto_settings.update(data["auto_settings"])

            if self.queue:
                log.info(f"fila recuperada do disco: {len(self.queue)} item(ns) pendente(s)")
        except (json.JSONDecodeError, OSError) as e:
            log.warning(f"nao consegui carregar {PERSIST_FILE}: {e}")

    def save_state(self):
        try:
            PERSIST_FILE.write_text(
                json.dumps({
                    "queue": list(self.queue),
                    "next_id": self.next_id,
                    "settings": self.settings,
                    "auto_settings": self.auto_settings
                }, ensure_ascii=False),
                encoding="utf-8",
            )
        except OSError as e:
            log.warning(f"nao consegui salvar {PERSIST_FILE}: {e}")

    # -----------------------------------------------------------------
    # Banimento permanente de nicks
    # -----------------------------------------------------------------
    def load_banned(self):
        if not BANNED_FILE.exists():
            return
        try:
            data = json.loads(BANNED_FILE.read_text(encoding="utf-8"))
            self.banned_nicks = set(n.lower() for n in data if isinstance(n, str))
            if self.banned_nicks:
                log.info(f"nicks banidos carregados: {len(self.banned_nicks)}")
        except (json.JSONDecodeError, OSError) as e:
            log.warning(f"nao consegui carregar {BANNED_FILE}: {e}")

    def save_banned(self):
        try:
            BANNED_FILE.write_text(
                json.dumps(sorted(self.banned_nicks), ensure_ascii=False),
                encoding="utf-8",
            )
        except OSError as e:
            log.warning(f"nao consegui salvar {BANNED_FILE}: {e}")

    async def ban_nick(self, nick: str):
        nick_lower = nick.lower()
        self.banned_nicks.add(nick_lower)
        # Remove da fila imediatamente se ainda estiver lá
        before = len(self.queue)
        self.queue = deque(i for i in self.queue if i["nick"].lower() != nick_lower)
        self.save_banned()
        if len(self.queue) < before:
            self.save_state()
            await self.broadcast_queue()
        log.info(f"nick '{nick}' BANIDO permanentemente.")
        await self.broadcast_banned_list()

    async def unban_nick(self, nick: str):
        self.banned_nicks.discard(nick.lower())
        self.save_banned()
        log.info(f"nick '{nick}' desbanido.")
        await self.broadcast_banned_list()

    async def broadcast_banned_list(self):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "banned_list", "nicks": sorted(self.banned_nicks)})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    # -----------------------------------------------------------------
    # Fila
    # -----------------------------------------------------------------
    def extract_candidates(self, message: str) -> list:
        """Retorna todos os tokens da mensagem que passam no formato de username do Roblox.
        A verificacao real de existencia e feita pela API (verify_roblox_user).
        """
        candidates = []
        for raw in message.strip().split():
            token = raw.strip('@,.!?:;-/|\'"()[]{}#$%^&*+=<>')
            if ROBLOX_USERNAME_RE.match(token) and len(token) >= 6:
                candidates.append(token)
        return candidates

    async def verify_roblox_user(self, username: str) -> bool:
        """Verifica se o username existe no Roblox via API oficial.
        Usa cache local de 10 minutos pra nao bater na API toda vez.
        Em caso de falha na API, tenta ate 3 vezes com backoff antes de rejeitar.
        """
        key = username.lower()
        now = time.time()

        # Verifica cache
        if key in _roblox_cache:
            exists, ts = _roblox_cache[key]
            if now - ts < CACHE_TTL:
                return exists

        # Chama a API do Roblox em uma thread pra nao bloquear o event loop
        payload = json.dumps({"usernames": [username], "excludeBannedUsers": False}).encode("utf-8")

        def _call():
            req = urllib.request.Request(
                ROBLOX_USERS_API,
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                },
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                return json.loads(resp.read().decode("utf-8"))

        max_tentativas = 3
        for tentativa in range(1, max_tentativas + 1):
            try:
                data = await asyncio.to_thread(_call)
                exists = bool(data.get("data"))
                _roblox_cache[key] = (exists, time.time())
                log.debug(f"API Roblox: '{username}' → {'existe' if exists else 'NAO existe'}")
                return exists
            except Exception as e:
                # Se for erro 429 (Too Many Requests), aceita por fallback imediatamente sem travar
                if isinstance(e, urllib.error.HTTPError) and e.code == 429:
                    log.warning(f"API Roblox retornou 429 (Too Many Requests) para '{username}' — aceitando nick por fallback imediatamente.")
                    return True

                if tentativa < max_tentativas:
                    espera = 2 ** tentativa  # 2s, 4s
                    log.warning(
                        f"API Roblox falhou para '{username}' "
                        f"(tentativa {tentativa}/{max_tentativas}): {e} — "
                        f"tentando novamente em {espera}s..."
                    )
                    await asyncio.sleep(espera)
                else:
                    log.warning(
                        f"API Roblox indisponivel para '{username}' apos "
                        f"{max_tentativas} tentativas: {e} — aceitando nick por fallback."
                    )
                    return True

        # Esgotou as tentativas: rejeita o nick pra nao poluir a fila
        return False


    async def broadcast_queue(self):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "queue_update", "items": list(self.queue)})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def broadcast_raw(self, data):
        """Envia qualquer payload JSON para todos os clientes conectados (desktop e mobile)."""
        if not self.connected_clients:
            return
        if isinstance(data, str):
            payload = data
        else:
            payload = json.dumps(data)
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def broadcast_speak(self, text: str):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "speak", "text": text})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def broadcast_trigger_end_live(self):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "triggerEndLive"})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def broadcast_settings(self):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "settings_update", "settings": self.settings})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def update_settings(self, new_settings: dict):
        allowed_keys = {"cooldown", "max_queue", "pickup_delay"}
        changed = False
        for key in allowed_keys:
            if key in new_settings:
                try:
                    value = int(new_settings[key])
                except (TypeError, ValueError):
                    continue
                if value < 0:
                    continue
                if self.settings.get(key) != value:
                    self.settings[key] = value
                    changed = True

        if "operation_mode" in new_settings:
            mode = str(new_settings["operation_mode"]).upper()
            if mode in ["FULL", "FALA", "ENTREGA", "MINI"]:
                if self.settings.get("operation_mode") != mode:
                    self.settings["operation_mode"] = mode
                    changed = True
                if mode in ["FULL", "ENTREGA"]:
                    self.settings["auto_send"] = True
                else:
                    self.settings["auto_send"] = False

        if "auto_send" in new_settings:
            val_bool = bool(new_settings["auto_send"])
            if self.settings.get("auto_send") != val_bool:
                self.settings["auto_send"] = val_bool
                changed = True

        if changed:
            log.info(f"configs atualizadas pelo painel: {self.settings}")
            self.save_state()
            await self.broadcast_settings()

    async def schedule_pickup(self, nick: str, sender: str, sender_id: str):
        """Espera um tempo (delay configuravel) antes de mandar pra fila de verdade."""
        # Checa banimento antes de aguardar delay (otimizacao)
        if nick.lower() in self.banned_nicks:
            log.debug(f"nick '{nick}' ignorado — banido permanentemente.")
            return
        await asyncio.sleep(self.settings['pickup_delay'])
        await self.add_to_queue(nick, sender, sender_id)

    async def add_to_queue(self, nick: str, sender: str, sender_id: str):
        now = time.time()

        # Checa banimento permanente
        if nick.lower() in self.banned_nicks:
            log.debug(f"nick '{nick}' ignorado — banido permanentemente.")
            return

        # cooldown por usuario do tiktok (evita flood da mesma pessoa)
        last = self.last_seen.get(sender_id, 0)
        if now - last < self.settings['cooldown']:
            self.total_rejected_cooldown += 1
            return

        # dedupe: nao deixa o mesmo nick entrar duas vezes enquanto ainda ta pendente
        if any(item["nick"].lower() == nick.lower() for item in self.queue):
            self.total_rejected_duplicate += 1
            log.info(f"nick '{nick}' ja esta na fila, ignorando repeticao de @{sender}")
            return

        if len(self.queue) >= self.settings['max_queue']:
            dropped = self.queue.popleft()
            log.warning(f"fila cheia ({self.settings['max_queue']}), descartando o mais antigo: {dropped['nick']}")

        item = {"id": self.next_id, "nick": nick, "sender": sender, "ts": now}
        self.next_id += 1
        self.queue.append(item)
        self.last_seen[sender_id] = now
        self.total_received += 1

        log.info(f"+ fila: {nick}  (enviado por @{sender})  [{len(self.queue)} na fila]")
        self.save_state()
        asyncio.create_task(supabase_sync("POST", "bgl_queue", {"id": item["id"], "nick": item["nick"], "sender": item["sender"], "sender_id": sender_id, "status": "pending", "robux": 0}))
        await self.broadcast_queue()

    async def remove_from_queue(self, item_id):
        before = len(self.queue)
        self.queue = deque(i for i in self.queue if i["id"] != item_id)
        if len(self.queue) < before:
            self.save_state()
            asyncio.create_task(supabase_sync("DELETE", f"bgl_queue?id=eq.{item_id}"))
            await self.broadcast_queue()

    async def add_manual(self, nick: str, sender: str = "manual"):
        """Adiciona (ou repete) um nick direto pelo painel, sem cooldown/dedupe —
        aqui e voce escolhendo na mao, entao a decisao e sua."""
        nick = (nick or "").strip()
        if not nick:
            return
        if not ROBLOX_USERNAME_RE.match(nick):
            log.warning(f"nick '{nick}' adicionado manualmente nao bate com o formato do Roblox, adicionando mesmo assim")

        if len(self.queue) >= self.settings['max_queue']:
            dropped = self.queue.popleft()
            log.warning(f"fila cheia ({self.settings['max_queue']}), descartando o mais antigo: {dropped['nick']}")

        item = {"id": self.next_id, "nick": nick, "sender": sender, "ts": time.time()}
        self.next_id += 1
        self.queue.append(item)
        self.total_received += 1

        log.info(f"+ fila (manual): {nick}  [{len(self.queue)} na fila]")
        self.save_state()
        asyncio.create_task(supabase_sync("POST", "bgl_queue", {"id": item["id"], "nick": item["nick"], "sender": item["sender"], "sender_id": "manual", "status": "pending", "robux": 0}))
        await self.broadcast_queue()

    # -----------------------------------------------------------------
    # Websocket: comunica com o frontend (queue.html) e a extensao
    # -----------------------------------------------------------------
    async def ws_handler(self, websocket):
        self.connected_clients.add(websocket)
        # Envia estado inicial completo para o cliente que acabou de conectar
        await websocket.send(json.dumps({"type": "queue_update", "items": list(self.queue)}))
        await websocket.send(json.dumps({"type": "settings_update", "settings": self.settings}))
        await websocket.send(json.dumps({"type": "auto_settings_update", "settings": self.auto_settings}))
        await websocket.send(json.dumps({
            "type": "live_status",
            "state": self.auto_live_state,
            "cycle": self.live_cycle,
            "phase_end_time": self.live_phase_end_time,
        }))
        await websocket.send(json.dumps({
            "type": "tiktok_status",
            "connected": self.tiktok_connected,
            "connecting": self.tiktok_connecting,
            "username": self.tiktok_username,
        }))
        # Envia lista de banidos para o cliente que acabou de conectar
        await websocket.send(json.dumps({"type": "banned_list", "nicks": sorted(self.banned_nicks)}))
        # Envia variações de fala salvas
        await websocket.send(json.dumps({"type": "speech_variations", "data": self._load_speech_raw()}))
        try:
            async for raw in websocket:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                mtype = msg.get("type")
                if mtype == "connect_tiktok":
                    await self.connect_tiktok(msg.get("username", ""))
                elif mtype == "disconnect_tiktok":
                    await self.disconnect_tiktok()
                elif mtype == "remove":
                    await self.remove_from_queue(msg.get("id"))
                elif mtype == "add":
                    await self.add_manual(msg.get("nick"), sender=msg.get("sender", "manual"))
                elif mtype == "add_robux":
                    nick = (msg.get("nick") or "").strip()
                    amount = int(msg.get("amount") or 0)
                    if nick and amount > 0:
                        for item in self.queue:
                            if item["nick"].lower() == nick.lower():
                                item["robux"] = amount
                        self.save_state()
                        asyncio.create_task(supabase_sync("PATCH", f"bgl_queue?nick=eq.{nick}", {"robux": amount}))
                        await self.broadcast_queue()
                elif mtype == "clear":
                    self.queue.clear()
                    self.save_state()
                    asyncio.create_task(supabase_sync("DELETE", "bgl_queue?id=gt.0"))
                    await self.broadcast_queue()
                elif mtype == "update_settings":
                    await self.update_settings(msg.get("settings", {}))
                elif mtype == "update_auto_settings":
                    await self.update_auto_settings(msg.get("settings", {}))
                elif mtype == "automation_step" or mtype == "purchase_finished":
                    await self.broadcast_raw(msg)
                    if mtype == "purchase_finished" and msg.get("status") == "success":
                        self.total_entregas += 1
                        u_done = msg.get("username", "")
                        amt_done = int(msg.get("amount") or 0)
                        if u_done:
                            asyncio.create_task(supabase_sync("POST", "bgl_deliveries", {"username": u_done, "amount": amt_done}))
                            asyncio.create_task(supabase_sync("PATCH", f"bgl_queue?nick=eq.{u_done}", {"status": "delivered"}))
                        # --- CHAT TRIGGERS (Entregas) ---
                        sp_data = self._load_speech_raw()
                        cats = sp_data.get("categorias", {})
                        for cat, cat_info in cats.items():
                            if isinstance(cat_info, dict) and "gatilhos" in cat_info:
                                entregas_gatilho = int(cat_info["gatilhos"].get("entregas") or 0)
                                if entregas_gatilho > 0 and self.total_entregas > 0 and self.total_entregas % entregas_gatilho == 0:
                                    result = self._pick_variation(cat)
                                    if result:
                                        import json
                                        asyncio.create_task(self.broadcast_raw(json.dumps({
                                            "type": "variation_picked", "categoria": cat, "text": result
                                        })))
                elif mtype == "start_auto_live":
                    await self.start_auto_live()
                elif mtype == "start_connection_test":
                    await self.start_connection_test()
                elif mtype == "stop_auto_live":
                    await self.stop_auto_live()
                elif mtype == "ban_nick":
                    nick = (msg.get("nick") or "").strip()
                    if nick:
                        await self.ban_nick(nick)
                elif mtype == "unban_nick":
                    nick = (msg.get("nick") or "").strip()
                    if nick:
                        await self.unban_nick(nick)
                elif mtype == "save_speech":
                    # Salva todo o objeto de variações de fala recebido do frontend mesclando com o existente
                    speech_state = self._load_speech_raw()
                    incoming = msg.get("data", {})
                    if isinstance(incoming, dict):
                        speech_state.update(incoming)
                    self._save_speech_raw(speech_state)
                elif mtype == "pick_variation":
                    # Sorteia uma variação sem repetir as últimas 2
                    categoria = msg.get("categoria", "")
                    result = self._pick_variation(categoria)
                    await websocket.send(json.dumps({"type": "variation_picked", "categoria": categoria, "text": result}))
        finally:
            self.connected_clients.discard(websocket)

    # -----------------------------------------------------------------
    # Sistema de variações de fala
    # -----------------------------------------------------------------
    def _load_speech_raw(self) -> dict:
        if not SPEECH_FILE.exists():
            return {"categorias": {}, "historico": {}}
        try:
            return json.loads(SPEECH_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {"categorias": {}, "historico": {}}

    def _save_speech_raw(self, data: dict):
        try:
            SPEECH_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as e:
            log.warning(f"nao consegui salvar {SPEECH_FILE}: {e}")

    def _pick_variation(self, categoria: str):
        """Sorteia uma variação da categoria, evitando repetir as últimas 2."""
        data = self._load_speech_raw()
        cats = data.get("categorias", {})
        hist = data.get("historico", {})
        
        variacoes = []
        cat_data = cats.get(categoria)
        if isinstance(cat_data, list):
            variacoes = [v if isinstance(v, str) else v.get("text", "") for v in cat_data]
        elif isinstance(cat_data, dict):
            raw_vars = cat_data.get("variacoes", [])
            variacoes = [v if isinstance(v, str) else v.get("text", "") for v in raw_vars]

        # Se não encontrou em categorias, procura em liveProofConfig ou falasList
        if not variacoes:
            if categoria.lower() in ["prova fake", "liveproof", "provafake"]:
                lp = data.get("liveProofConfig", {})
                versions = lp.get("versions", [])
                variacoes = [v.get("text", "") for v in versions if isinstance(v, dict) and v.get("text")]
            else:
                falas = data.get("falasList", [])
                for f in falas:
                    if isinstance(f, dict) and (f.get("name", "").lower() == categoria.lower() or str(f.get("id")) == str(categoria)):
                        versions = f.get("versions", [])
                        variacoes = [v.get("text", "") for v in versions if isinstance(v, dict) and v.get("text")]
                        if not variacoes and f.get("text"):
                            variacoes = [f.get("text")]
                        break

        variacoes = [v for v in variacoes if v]
        if not variacoes:
            return ""
            
        ultimas = hist.get(categoria, [])
        # Filtra as candidatas: remove as últimas 2 se houver mais opções
        candidatas = [i for i, _ in enumerate(variacoes) if i not in ultimas]
        if not candidatas:
            candidatas = list(range(len(variacoes)))  # todas disponíveis se não há outra opção
            
        import random
        escolhido_idx = random.choice(candidatas)
        
        # Atualiza histórico
        novo_hist = (ultimas + [escolhido_idx])[-2:]
        if "historico" not in data:
            data["historico"] = {}
        data["historico"][categoria] = novo_hist
        self._save_speech_raw(data)
        
        return variacoes[escolhido_idx]

    # -----------------------------------------------------------------
    # Discord Webhook — envia estatisticas quando a live terminar
    # -----------------------------------------------------------------
    async def send_discord_webhook_start(self, username: str):
        """Envia um embed de aviso verde pro Discord quando a live iniciar."""
        if not DISCORD_WEBHOOK_URL:
            return
        
        embed = {
            "title": f"🟢 Live de @{username} INICIADA!",
            "description": "O bot conectou com sucesso e já está lendo o chat.",
            "color": 0x3DDC84,  # verde
            "footer": {
                "text": "BGL Queue — Sistema de fila de Robux"
            },
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        
        payload = json.dumps({"embeds": [embed]}).encode("utf-8")
        try:
            req = urllib.request.Request(
                DISCORD_WEBHOOK_URL,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                log.info(f"webhook de inicio enviado! Status: {resp.status}")
        except Exception as e:
            log.error(f"erro ao enviar webhook de inicio: {e}")

    async def send_discord_webhook(self, username: str):
        """Monta e envia o embed com as estatisticas da live pro Discord."""
        if not DISCORD_WEBHOOK_URL:
            return

        # Calcula duracao da live
        if self.live_start_time:
            duracao_seg = int(time.time() - self.live_start_time)
            horas = duracao_seg // 3600
            minutos = (duracao_seg % 3600) // 60
            segundos = duracao_seg % 60
            duracao_str = f"{horas:02d}:{minutos:02d}:{segundos:02d}"
        else:
            duracao_str = "desconhecida"

        # Lista dos nicks que sobraram na fila
        nicks_restantes = [item["nick"] for item in self.queue]
        if nicks_restantes:
            fila_str = "\n".join(f"`{n}`" for n in nicks_restantes[:20])
            if len(nicks_restantes) > 20:
                fila_str += f"\n*... e mais {len(nicks_restantes) - 20} nicks*"
        else:
            fila_str = "*fila vazia*"

        total_rejeitados = self.total_rejected_duplicate + self.total_rejected_cooldown

        embed = {
            "title": f"📺 Live de @{username} encerrada!",
            "color": 0xFF0050,  # vermelho TikTok
            "fields": [
                {
                    "name": "⏱️ Duração da live",
                    "value": duracao_str,
                    "inline": True,
                },
                {
                    "name": "✅ Nicks aceitos",
                    "value": str(self.total_received),
                    "inline": True,
                },
                {
                    "name": "❌ Rejeitados (total)",
                    "value": str(total_rejeitados),
                    "inline": True,
                },
                {
                    "name": "🔁 Rejeitados (duplicado)",
                    "value": str(self.total_rejected_duplicate),
                    "inline": True,
                },
                {
                    "name": "⏳ Rejeitados (cooldown)",
                    "value": str(self.total_rejected_cooldown),
                    "inline": True,
                },
                {
                    "name": f"📋 Fila final ({len(self.queue)} pessoas)",
                    "value": fila_str,
                    "inline": False,
                },
            ],
            "footer": {
                "text": "BGL Queue — Sistema de fila de Robux"
            },
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }

        payload = json.dumps({"embeds": [embed]}).encode("utf-8")

        try:
            req = urllib.request.Request(
                DISCORD_WEBHOOK_URL,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                log.info(f"webhook Discord enviado com sucesso! Status: {resp.status}")
        except Exception as e:
            log.error(f"erro ao enviar webhook Discord: {e}")

    # -----------------------------------------------------------------
    # TikTokLive: escuta o chat da live, com reconexao automatica
    # -----------------------------------------------------------------
    def make_tiktok_client(self, username: str) -> TikTokLiveClient:
        client = TikTokLiveClient(unique_id=username)
        self.tiktok_client = client

        @client.on(ConnectEvent)
        async def on_connect(_: ConnectEvent):
            self.live_start_time = time.time()
            self.tiktok_connected = True
            self.tiktok_connecting = False
            log.info(f"conectado na live de @{username}")
            await self.send_discord_webhook_start(username)
            await self.broadcast_tiktok_status()

        @client.on(DisconnectEvent)
        async def on_disconnect(_: DisconnectEvent):
            self.tiktok_connected = False
            self.tiktok_connecting = False
            log.warning("desconectado da live (ela pode ter acabado, ou caiu a conexao)")
            await self.broadcast_tiktok_status()
            # Notifica clientes mobile sobre a desconexao
            await self.broadcast_raw({"type": "tiktok_disconnected", "message": "Live TikTok desconectou!"})
            # Envia as estatisticas da live pro Discord
            await self.send_discord_webhook(username)

        @client.on(CommentEvent)
        async def on_comment(event: CommentEvent):
            # --- CHAT TRIGGERS (Falas) ---
            data = self._load_speech_raw()
            cats = data.get("categorias", {})
            msg_lower = event.comment.lower()
            for cat, cat_info in cats.items():
                if isinstance(cat_info, dict) and "gatilhos" in cat_info:
                    palavras = cat_info["gatilhos"].get("palavras", "")
                    if palavras:
                        lista_palavras = [p.strip().lower() for p in palavras.split(",") if p.strip()]
                        for p in lista_palavras:
                            # Se for uma palavra sozinha (ex: !audio), a pessoa pode ter mandado só isso ou no meio da frase
                            if p in msg_lower:
                                result = self._pick_variation(cat)
                                if result:
                                    import json
                                    asyncio.create_task(self.broadcast_raw(json.dumps({
                                        "type": "variation_picked", "categoria": cat, "text": result
                                    })))
                                break

            # Gatilho especial de Prova Fake por palavras de gravação
            fake_keywords = ["gravad", "gravac", "gravando", "gravou", "fake", "ta gravado", "tá gravado", "eh gravado", "é gravado", "live gravada"]
            if any(kw in msg_lower for kw in fake_keywords):
                res_fake = self._pick_variation("Prova Fake")
                asyncio.create_task(self.broadcast_raw({
                    "type": "variation_picked",
                    "categoria": "Prova Fake",
                    "text": res_fake,
                    "source": "chat_detect"
                }))
            # ------------------------------

            candidates = self.extract_candidates(event.comment)
            if not candidates:
                return
            sender = event.user.nickname or event.user.unique_id
            sender_id = str(event.user.unique_id)

            async def verify_and_schedule():
                for candidate in candidates:
                    exists = await self.verify_roblox_user(candidate)
                    if exists:
                        log.info(f"nick '{candidate}' verificado na API do Roblox ✓ (de @{sender})"
                                 f" — aguardando {self.settings['pickup_delay']}s")
                        await self.schedule_pickup(candidate, sender, sender_id)
                        return  # usa so o primeiro nick valido encontrado
                log.debug(f"nenhum nick valido encontrado na mensagem de @{sender}: {event.comment!r}")

            asyncio.create_task(verify_and_schedule())

        return client

    async def broadcast_tiktok_status(self):
        payload = {
            "type": "tiktok_status",
            "connected": self.tiktok_connected,
            "connecting": self.tiktok_connecting,
            "username": self.tiktok_username,
        }
        await self.broadcast_raw(payload)
        asyncio.create_task(supabase_sync("POST", "bgl_config", {
            "key": "tiktok_status",
            "value": {
                "connected": self.tiktok_connected,
                "connecting": self.tiktok_connecting,
                "username": self.tiktok_username
            }
        }))

    async def connect_tiktok(self, username: str):
        user = (username or "").strip().lstrip("@")
        if not user:
            log.warning("Tentativa de conectar TikTok com username vazio.")
            return

        if self.tiktok_connected and self.tiktok_username == user:
            log.info(f"TikTok já está conectado para @{user}")
            await self.broadcast_tiktok_status()
            return

        await self.disconnect_tiktok(silent=True)

        self.tiktok_username = user
        self.tiktok_connecting = True
        self.tiktok_connected = False

        try:
            Path("ultimo_perfil.txt").write_text(user, encoding="utf-8")
        except Exception as e:
            log.warning(f"Não foi possível salvar ultimo_perfil.txt: {e}")

        log.info(f"Iniciando conexão TikTok Live para @{user}...")
        await self.broadcast_tiktok_status()

        self.tiktok_task = asyncio.create_task(self.run_tiktok_with_reconnect(user))

    async def disconnect_tiktok(self, silent: bool = False):
        if self.tiktok_task and not self.tiktok_task.done():
            self.tiktok_task.cancel()
            try:
                await self.tiktok_task
            except (asyncio.CancelledError, Exception):
                pass
            self.tiktok_task = None

        if self.tiktok_client:
            try:
                if hasattr(self.tiktok_client, "disconnect"):
                    await self.tiktok_client.disconnect()
                elif hasattr(self.tiktok_client, "stop"):
                    await self.tiktok_client.stop()
            except Exception:
                pass
            self.tiktok_client = None

        self.tiktok_connected = False
        self.tiktok_connecting = False
        if not silent:
            log.info("TikTok Live desconectado.")
            await self.broadcast_tiktok_status()

    async def run_tiktok_with_reconnect(self, username: str):
        """Fica tentando reconectar sozinho se a live cair ou a conexao falhar."""
        backoff = 5  # segundos, cresce a cada falha ate um teto
        max_backoff = 60

        while True:
            try:
                client = self.make_tiktok_client(username)
                self.tiktok_client = client
                self.tiktok_connected = False
                self.tiktok_connecting = True
                await self.broadcast_tiktok_status()
                await client.start()
                backoff = 5
            except asyncio.CancelledError:
                log.info(f"Monitoramento da live de @{username} cancelado.")
                break
            except Exception as e:
                log.error(f"erro conectando na live de @{username}: {e}")
                self.tiktok_connected = False
                self.tiktok_connecting = False
                await self.broadcast_tiktok_status()

            if asyncio.current_task() and asyncio.current_task().cancelled():
                break

            log.info(f"tentando reconectar em {backoff}s...")
            try:
                await asyncio.sleep(backoff)
            except asyncio.CancelledError:
                break
            backoff = min(backoff * 2, max_backoff)

    # -----------------------------------------------------------------
    # Broadcast de status da live automatica
    # -----------------------------------------------------------------
    async def broadcast_live_status(self):
        if not self.connected_clients:
            return
        payload = json.dumps({
            "type": "live_status",
            "state": self.auto_live_state,
            "cycle": self.live_cycle,
            "phase_end_time": self.live_phase_end_time,
        })
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def broadcast_auto_settings(self):
        if not self.connected_clients:
            return
        payload = json.dumps({"type": "auto_settings_update", "settings": self.auto_settings})
        stale = []
        for ws in self.connected_clients:
            try:
                await ws.send(payload)
            except websockets.exceptions.ConnectionClosed:
                stale.append(ws)
        for ws in stale:
            self.connected_clients.discard(ws)

    async def update_auto_settings(self, new_settings: dict):
        int_keys = {"live_duration_minutes", "pause_between_lives_minutes", "wait_after_open_seconds", "repeat_times"}
        str_keys = {"live_url", "chrome_path"}
        changed = False
        for key in int_keys:
            if key in new_settings:
                try:
                    value = int(new_settings[key])
                    if value < 0:
                        continue
                    if self.auto_settings.get(key) != value:
                        self.auto_settings[key] = value
                        changed = True
                except (TypeError, ValueError):
                    continue
        for key in str_keys:
            if key in new_settings:
                raw_val = new_settings[key]
                if raw_val is None:
                    value = None
                else:
                    value = str(raw_val).strip()
                if self.auto_settings.get(key) != value:
                    self.auto_settings[key] = value
                    changed = True
        if changed:
            log.info(f"configs de auto live atualizadas: {self.auto_settings}")
            self.save_state()
            await self.broadcast_auto_settings()

    # -----------------------------------------------------------------
    # Automacao de Live: helpers de sistema
    # -----------------------------------------------------------------
    def _focar_tiktok_studio(self):
        """Traz a janela do TikTok Studio para frente.
        Procura por 'Studio' no nome, pois as vezes o nome é apenas 'LIVE Studio'.
        """
        hwnd = None
        try:
            import win32gui
            import win32con

            def _enum(h, _):
                nonlocal hwnd
                titulo = win32gui.GetWindowText(h)
                if "Studio" in titulo and win32gui.IsWindowVisible(h):
                    hwnd = h

            win32gui.EnumWindows(_enum, None)

            if hwnd:
                titulo_janela = win32gui.GetWindowText(hwnd)
                log.info(f"Janela encontrada! HWND: {hwnd} | Titulo: '{titulo_janela}'")
                
                win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
                time.sleep(0.4)
                
                try:
                    win32gui.BringWindowToTop(hwnd)
                    win32gui.SetForegroundWindow(hwnd)
                    log.info("SetForegroundWindow chamado com sucesso.")
                except Exception as e_focus:
                    log.warning(f"Aviso ao trazer para frente (SetForegroundWindow): {e_focus}")
                
                time.sleep(0.5)
                
                log.info("Janela do Studio focada.")
                return True
            else:
                log.warning("Nenhuma janela contendo 'Studio' visível foi encontrada!")
        except Exception as e:
            log.warning(f"Erro geral ao tentar focar: {e}")
        return False

    def _encontrar_chrome(self) -> str:
        chrome_path = self.auto_settings.get("chrome_path", "")
        if chrome_path and os.path.exists(chrome_path):
            return chrome_path
        candidatos = [
            r"C:\Program Files\Google\Chrome\Application\chrome.exe",
            r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
            os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
        ]
        for c in candidatos:
            if os.path.exists(c):
                return c
        return "chrome"

    def _abrir_chrome(self, url: str):
        chrome = self._encontrar_chrome()
        try:
            subprocess.Popen([
                chrome,
                "--new-window",
                "--kiosk",
                url
            ])
            log.info(f"Chrome aberto: {url}")
        except Exception as e:
            log.error(f"Erro ao abrir Chrome: {e}")


    def _fechar_chrome(self):
        try:
            subprocess.run(
                ["taskkill", "/f", "/im", "chrome.exe"],
                capture_output=True,
                creationflags=0x08000000,  # CREATE_NO_WINDOW
            )
            log.info("Chrome fechado.")
        except Exception as e:
            log.error(f"Erro ao fechar Chrome: {e}")

    def _enviar_atalho(self, atalho: str, max_tentativas: int = 3):
        """Envia atalho de teclado usando a biblioteca keyboard e pyautogui como fallback."""
        if not _KEYBOARD_OK:
            log.error("modulo 'keyboard' nao disponivel — instale com: pip install keyboard")
        
        pyautogui_keys = atalho.lower().split('+') if '+' in atalho else [atalho.lower()]
        
        for tentativa in range(1, max_tentativas + 1):
            try:
                # 1. Tenta usar a biblioteca keyboard
                if _KEYBOARD_OK:
                    if "+" in atalho:
                        keys = atalho.split("+")
                        for k in keys:
                            keyboard.press(k)
                        time.sleep(0.1)
                        for k in reversed(keys):
                            keyboard.release(k)
                    else:
                        keyboard.send(atalho)
                    log.info(f"Atalho enviado (keyboard): {atalho}")
                
                # 2. Tenta usar pyautogui como redundância/garantia
                try:
                    import pyautogui
                    pyautogui.hotkey(*pyautogui_keys)
                    log.info(f"Atalho enviado (pyautogui): {atalho}")
                except Exception as e_py:
                    log.warning(f"Falha ao enviar por pyautogui: {e_py}")
                
                return
            except Exception as e:
                if tentativa < max_tentativas:
                    log.warning(f"Falha ao enviar '{atalho}' (tentativa {tentativa}): {e} — tentando novamente...")
                    time.sleep(0.5)
                else:
                    log.error(f"Nao foi possivel enviar '{atalho}' apos {max_tentativas} tentativas: {e}")

    # -----------------------------------------------------------------
    # Automacao de Live: controle e loop principal
    # -----------------------------------------------------------------
    async def start_connection_test(self):
        if self.auto_live_task and not self.auto_live_task.done():
            log.warning("Loop de automação ou teste já está rodando.")
            return
        self.live_cycle = 0
        self.auto_live_state = "idle"
        self.auto_live_task = asyncio.create_task(self.run_connection_test())
        log.info("Teste de conexão iniciado.")

    async def run_connection_test(self):
        try:
            log.info("=========================================")
            log.info("INICIANDO TESTE DE CONEXÃO (20 SEGUNDOS)")
            log.info("Você tem 5 SEGUNDOS para clicar na janela")
            log.info("do TikTok Studio e deixar ela na frente!")
            log.info("=========================================")
            for i in range(5, 0, -1):
                log.info(f"Iniciando teste em {i}...")
                await asyncio.sleep(1)

            # --- FASE 1: Live de teste no ar ---
            self.auto_live_state = "live"
            self.live_phase_end_time = time.time() + 20
            await self.broadcast_live_status()

            # Abre o Chrome imediatamente
            s = self.auto_settings
            url = s.get("live_url", "https://www.roblox.com/upgrades/robux?ctx=navpopover")
            await asyncio.to_thread(self._abrir_chrome, url)
            await asyncio.to_thread(self._abrir_tikfinity)

            # Envia atalho para abrir live
            await asyncio.to_thread(self._focar_tiktok_studio)
            await asyncio.to_thread(self._enviar_atalho, "ctrl+shift+w")
            log.info("Enviado atalho para abrir live (ctrl+shift+w).")

            # Aguarda os 20 segundos atualizando o status do timer
            while time.time() < self.live_phase_end_time:
                await self.broadcast_live_status()
                restante = self.live_phase_end_time - time.time()
                await asyncio.sleep(min(1, max(0.1, restante)))

            # --- Encerra a live ---
            log.info("Tempo do teste esgotado: encerrando live...")
            await asyncio.to_thread(self._fechar_chrome)
            await asyncio.sleep(2)

            for attempt in range(3):
                log.info(f"Tentativa {attempt + 1} de encerrar a live no teste...")
                await asyncio.to_thread(self._focar_tiktok_studio)
                await asyncio.sleep(1)
                await asyncio.to_thread(self._enviar_atalho, "ctrl+shift+e")
                await asyncio.sleep(1.5)
                # Envia Enter caso tenha modal de confirmação do TikTok Studio
                await asyncio.to_thread(self._enviar_atalho, "enter")
                await asyncio.sleep(3)

        except asyncio.CancelledError:
            log.info("Teste de conexão cancelado.")
        except Exception as e:
            log.error(f"Erro no teste de conexão: {e}")
        finally:
            self.auto_live_state = "idle"
            self.live_phase_end_time = 0.0
            await self.broadcast_live_status()

    async def start_auto_live(self):
        if self.auto_live_task and not self.auto_live_task.done():
            log.warning("Loop de auto live ja esta rodando.")
            return
        self.live_cycle = 0
        self.auto_live_state = "idle"
        self.auto_live_task = asyncio.create_task(self.run_auto_live())
        log.info("Loop de auto live iniciado.")

    async def stop_auto_live(self):
        was_live = self.auto_live_state == "live"
        if self.auto_live_task and not self.auto_live_task.done():
            self.auto_live_task.cancel()
            try:
                await self.auto_live_task
            except asyncio.CancelledError:
                pass
        self.auto_live_state = "idle"
        self.live_phase_end_time = 0.0
        await asyncio.to_thread(self._fechar_chrome)
        if was_live:
            while True:
                await asyncio.sleep(1)
                await asyncio.to_thread(self._focar_tiktok_studio)
                await asyncio.sleep(1)
                await asyncio.to_thread(self._enviar_atalho, "ctrl+shift+e")
                await asyncio.sleep(1.5)
                await asyncio.to_thread(self._enviar_atalho, "enter")
                log.info("Enviado atalho para fechar live ao parar (ctrl+shift+e + enter). Esperando 5s para checar status...")
                await asyncio.sleep(5)
                if not self.tiktok_connected:
                    log.info("Sucesso: Live parada e desconectada pelo stop_auto_live!")
                    break
                log.warning("Aviso: Live não encerrou ao parar. Tentando novamente...")
        log.info("Loop de auto live stopped.")
        await self.broadcast_live_status()

    async def run_auto_live(self):
        """Loop principal de automacao: abre live, aguarda, encerra, pausa, repete."""
        try:
            log.info("=========================================")
            log.info("Você tem 5 SEGUNDOS para clicar na janela")
            log.info("do TikTok Studio e deixar ela na frente!")
            log.info("=========================================")
            for i in range(5, 0, -1):
                log.info(f"Iniciando em {i}...")
                await asyncio.sleep(1)

            while True:
                s = self.auto_settings
                self.live_cycle += 1
                log.info(f"=== AUTO LIVE — CICLO #{self.live_cycle} ===")

                # --- FASE 1: Live no ar ---
                self.auto_live_state = "live"
                self.live_phase_end_time = time.time() + s["live_duration_minutes"] * 60
                await self.broadcast_live_status()

                # Abre o Chrome imediatamente para não bloquear
                url = s.get("live_url", "https://www.roblox.com/upgrades/robux?ctx=navpopover")
                await asyncio.to_thread(self._abrir_chrome, url)

                while True:
                    await asyncio.to_thread(self._focar_tiktok_studio)
                    await asyncio.to_thread(self._enviar_atalho, "ctrl+shift+w")
                    log.info("Enviado atalho para abrir live (ctrl+shift+w). Esperando 5s para checar status...")
                    await asyncio.sleep(5)
                    if self.tiktok_connected:
                        log.info("Sucesso: Live aberta e conectada!")
                        break
                    log.warning("Aviso: Live ainda não abriu. Tentando novamente...")

                spoken_close = False
                while time.time() < self.live_phase_end_time:
                    remaining = self.live_phase_end_time - time.time()
                    if remaining <= 10 and not spoken_close:
                        await self.broadcast_trigger_end_live()
                        spoken_close = True
                    await self.broadcast_live_status()
                    restante = self.live_phase_end_time - time.time()
                    await asyncio.sleep(min(5, max(0.5, restante)))

                # --- Encerra a live ---
                log.info(f"Ciclo #{self.live_cycle}: encerrando live...")
                await asyncio.to_thread(self._fechar_chrome)
                await asyncio.sleep(2)

                while True:
                    await asyncio.to_thread(self._focar_tiktok_studio)
                    await asyncio.sleep(1)  # Garante que focou
                    await asyncio.to_thread(self._enviar_atalho, "ctrl+shift+e")
                    await asyncio.sleep(1.5)
                    await asyncio.to_thread(self._enviar_atalho, "enter")
                    log.info("Enviado atalho para fechar live (ctrl+shift+e + enter). Esperando 5s para checar status...")
                    await asyncio.sleep(5)
                    if not self.tiktok_connected:
                        log.info("Sucesso: Live encerrada e desconectada!")
                        break
                    log.warning("Aviso: Live ainda não fechou. Tentando novamente...")
                await asyncio.sleep(1)

                # Verifica limite de ciclos
                repeat_times = s.get("repeat_times", 0)
                if repeat_times > 0 and self.live_cycle >= repeat_times:
                    log.info(f"Numero maximo de ciclos ({repeat_times}) atingido. Parando.")
                    break

                # --- FASE 2: Pausa entre lives ---
                self.auto_live_state = "paused"
                self.live_phase_end_time = time.time() + s["pause_between_lives_minutes"] * 60
                await self.broadcast_live_status()
                log.info(f"Pausa de {s['pause_between_lives_minutes']} min antes do proximo ciclo...")

                while time.time() < self.live_phase_end_time:
                    await self.broadcast_live_status()
                    restante = self.live_phase_end_time - time.time()
                    await asyncio.sleep(min(5, max(0.5, restante)))

        except asyncio.CancelledError:
            log.info("Loop de auto live cancelado.")
        except Exception as e:
            log.error(f"Erro no loop de auto live: {e}")
        finally:
            self.auto_live_state = "idle"
            self.live_phase_end_time = 0.0
            await self.broadcast_live_status()

    # -----------------------------------------------------------------
    # Servidor HTTP simples so pra servir o queue.html
    # -----------------------------------------------------------------
    def run_http_server(self):
        # Garante que o diretório de trabalho do servidor HTTP seja a pasta do próprio script
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        
        handler = AuthHTTPRequestHandler
        server_address = ("0.0.0.0", self.args.http_port)
        
        # Cria o server HTTP permitindo reuso de porta e rodando de forma assíncrona/multithreaded
        try:
            from http.server import ThreadingHTTPServer
            httpd = ThreadingHTTPServer(server_address, handler)
        except ImportError:
            from http.server import HTTPServer
            class ReusableHTTPServer(HTTPServer):
                allow_reuse_address = True
            httpd = ReusableHTTPServer(server_address, handler)

        local_ip = get_local_ip()
        base_local   = f"http://{local_ip}:{self.args.http_port}"
        queue_url    = f"http://127.0.0.1:{self.args.http_port}/queue.html"
        overlay_url  = f"http://127.0.0.1:{self.args.http_port}/overlay.html"
        mobile_url   = f"{base_local}/mobile.html"

        log.info(f"pagina da fila em: {queue_url}")
        log.info(f"overlay em: {overlay_url}")

        # Exibe link e QR Code do app mobile
        print_mobile_url(mobile_url)

        # Inicia Roblox, Overlay e Dashboard no Google Chrome
        try:
            chrome_exe = self._encontrar_chrome()
            subprocess.Popen([chrome_exe, "--new-window", "https://www.roblox.com/upgrades/robux?ctx=navpopover"])
            subprocess.Popen([chrome_exe, "--new-window", queue_url, overlay_url])
            log.info("Chrome iniciado com Roblox, Overlay e Dashboard.")
        except Exception as e:
            log.warning(f"Erro ao abrir Chrome: {e}")
        httpd.serve_forever()

    async def run_ws_server(self):
        async with websockets.serve(self.ws_handler, "0.0.0.0", self.args.ws_port, max_size=20_000_000):
            log.info(f"websocket rodando em ws://0.0.0.0:{self.args.ws_port}")
            await asyncio.Future()  # roda pra sempre

    # -----------------------------------------------------------------
    # Estatisticas periodicas (util pra saber se o filtro ta rejeitando demais)
    # -----------------------------------------------------------------
    async def print_stats_periodically(self):
        while True:
            await asyncio.sleep(300)  # a cada 5 min
            log.info(
                f"estatisticas — aceitos: {self.total_received} | "
                f"rejeitados (duplicado): {self.total_rejected_duplicate} | "
                f"rejeitados (cooldown): {self.total_rejected_cooldown} | "
                f"fila atual: {len(self.queue)}"
            )
    async def speech_timers_loop(self):
        timers = {} # cat_name -> seconds left
        while True:
            await asyncio.sleep(1)
            data = self._load_speech_raw()
            cats = data.get("categorias", {})
            for cat, cat_info in cats.items():
                if isinstance(cat_info, dict) and "gatilhos" in cat_info:
                    min_gatilho = int(cat_info["gatilhos"].get("minutos") or 0)
                    if min_gatilho > 0:
                        if cat not in timers or timers[cat] > min_gatilho * 60:
                            timers[cat] = min_gatilho * 60
                        else:
                            timers[cat] -= 1
                            if timers[cat] <= 0:
                                # TIME TO TRIGGER
                                timers[cat] = min_gatilho * 60
                                result = self._pick_variation(cat)
                                if result:
                                    import json
                                    asyncio.create_task(self.broadcast_raw(json.dumps({
                                        "type": "variation_picked", "categoria": cat, "text": result
                                    })))

    async def supabase_config_loop(self):
        """Monitora comandos de conectar/desconectar TikTok e modos vindos do Supabase (Vercel)."""
        while True:
            await asyncio.sleep(3)
            try:
                def _fetch_cfg():
                    url = f"{SUPABASE_URL}/rest/v1/bgl_config?select=*"
                    headers = {
                        "apikey": SUPABASE_KEY,
                        "Authorization": f"Bearer {SUPABASE_KEY}"
                    }
                    req = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(req, timeout=4) as resp:
                        return json.loads(resp.read().decode())

                loop = asyncio.get_running_loop()
                data = await loop.run_in_executor(None, _fetch_cfg)
                if data and isinstance(data, list):
                    for item in data:
                        k = item.get("key")
                        cfg_val = item.get("value")
                        if isinstance(cfg_val, str):
                            try:
                                cfg_val = json.loads(cfg_val)
                            except Exception:
                                pass

                        if k == "tiktok_status" and isinstance(cfg_val, dict):
                            is_connecting = cfg_val.get("connecting", False)
                            is_connected = cfg_val.get("connected", False)
                            target_user = (cfg_val.get("username") or "").strip().lstrip("@")

                            if is_connecting and target_user:
                                if not self.tiktok_connected or self.tiktok_username != target_user:
                                    log.info(f"[Supabase Cloud] Ordem remota para conectar TikTok: @{target_user}")
                                    await self.connect_tiktok(target_user)
                            elif not is_connecting and not is_connected and self.tiktok_connected:
                                log.info("[Supabase Cloud] Ordem remota para desconectar TikTok.")
                                await self.disconnect_tiktok()

                        elif k == "operation_mode" and isinstance(cfg_val, dict):
                            mode = str(cfg_val.get("operation_mode", "")).upper()
                            if mode in ["FULL", "FALA", "ENTREGA", "MINI"]:
                                if self.settings.get("operation_mode") != mode:
                                    log.info(f"[Supabase Cloud] Sincronizando modo de operação: {mode}")
                                    self.settings["operation_mode"] = mode
                                    if mode in ["FULL", "ENTREGA"]:
                                        self.settings["auto_send"] = True
                                    else:
                                        self.settings["auto_send"] = False
                                    await self.broadcast(json.dumps({
                                        "type": "settings_update",
                                        "settings": self.settings
                                    }))
            except Exception as e:
                log.debug(f"[Supabase Poller] erro transitório: {e}")

    async def main(self, username: str = ""):
        threading.Thread(target=self.run_http_server, daemon=True).start()

        target_user = (username or self.tiktok_username).lstrip("@").strip()
        tasks = [
            self.run_ws_server(),
            self.print_stats_periodically(),
            self.speech_timers_loop(),
            self.supabase_config_loop(),
        ]
        if target_user:
            log.info(f"Conectando automaticamente na live de @{target_user}...")
            tasks.append(self.connect_tiktok(target_user))
        else:
            log.info("Nenhum perfil do TikTok configurado na inicialização. Você pode conectar direto pelo painel web (queue.html).")

        await asyncio.gather(*tasks)


def parse_args(args=None):
    env_port = int(os.environ.get("PORT", 8082))
    parser = argparse.ArgumentParser(description="BGL Queue — le o chat da live e monta a fila de nicks")
    parser.add_argument("username", nargs="?", default="", help="seu @ do TikTok, com ou sem @ (opcional, pode conectar pelo painel web)")
    parser.add_argument("--cooldown", type=int, default=300, help="segundos entre 2 entradas do mesmo usuario (padrao: 300)")
    parser.add_argument("--max-queue", type=int, default=500, help="tamanho maximo da fila (padrao: 500)")
    parser.add_argument("--ws-port", type=int, default=8765, help="porta do websocket (padrao: 8765)")
    parser.add_argument("--http-port", type=int, default=env_port, help="porta da pagina queue.html (padrao: 8082 ou $PORT)")
    parser.add_argument(
        "--pickup-delay", type=int, default=10,
        help="segundos de espera entre pegar o nick no chat e mandar pra fila de verdade (padrao: 10)"
    )
    parser.add_argument(
        "--api-key",
        default=EULER_API_KEY or None,
        help="API key da Euler Stream (eulerstream.com/dashboard) — aumenta o rate limit da lib TikTokLive. "
             "Se voce ja colou a chave na constante EULER_API_KEY no topo do arquivo, nao precisa passar aqui.",
    )
    return parser.parse_args(args)


if __name__ == "__main__":
    args = parse_args()
    tiktok_username = (args.username or "").lstrip("@")

    if args.api_key:
        WebDefaults.tiktok_sign_api_key = args.api_key
        log.info("API key da Euler Stream configurada.")
    else:
        log.warning(
            "rodando sem API key da Euler Stream — se estiver batendo rate limit, "
            "pega uma gratis em https://www.eulerstream.com/dashboard e roda com --api-key SUACHAVE"
        )

    server = QueueServer(args)
    log.info(f"delay de {args.pickup_delay}s entre pegar o nick e mandar pra fila")
    try:
        asyncio.run(server.main(tiktok_username))
    except KeyboardInterrupt:
        log.info("encerrado pelo usuario.")
        server.save_state()