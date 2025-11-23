#!/bin/bash

# Script de instalación completo: Proxy + Nginx + Dashboard Profesional
# AWS EC2 Free Tier

set -e

echo "=========================================="
echo "🚀 Instalación Proxy + Dashboard Profesional"
echo "=========================================="
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# CREDENCIALES PREDEFINIDAS
# ============================================
PROXY_USER="admin"
PROXY_PASS="ProxySecure2024!"
PROXY_PORT="8080"
NGINX_STATUS_PORT="8081"
# ============================================

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
  else
    print_error "No se pudo detectar el sistema operativo"
    exit 1
  fi
  print_info "Sistema detectado: $OS $VERSION"
}

install_nodejs() {
  print_info "Instalando Node.js..."
  if [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    sudo yum update -y
    curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
    sudo yum install -y nodejs
  elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    sudo apt-get update
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    print_error "Sistema operativo no soportado: $OS"
    exit 1
  fi
  print_info "Node.js: $(node --version)"
}

create_proxy_file() {
  print_info "Creando /opt/proxy/proxy.js con métricas..."
  sudo mkdir -p /opt/proxy
  sudo chown "$USER:$USER" /opt/proxy
  
  cat > /opt/proxy/proxy.js <<'PROXYEOF'
const http = require('http');
const https = require('https');
const url = require('url');
const net = require('net');
const crypto = require('crypto');

class AuthenticatedProxy {
  constructor(port = 8080, username = 'admin', password = 'password123') {
    this.port = port;
    this.username = username;
    this.password = password;
    this.server = null;
    this.connections = new Set();

    // Métricas
    this.metrics = {
      httpRequests: 0,
      httpsTunnels: 0,
      errors: 0,
      startTime: Date.now()
    };

    this.validAuth = Buffer.from(`${username}:${password}`).toString('base64');
  }

  start() {
    this.server = http.createServer((req, res) => {
      // Endpoint de status (sin auth para que Nginx lo consulte)
      if (req.url === '/status' && req.method === 'GET') {
        return this.handleStatusEndpoint(req, res);
      }

      if (!this.authenticate(req, res)) return;
      this.metrics.httpRequests++;
      this.handleHttpRequest(req, res);
    });

    this.server.on('connect', (req, clientSocket, head) => {
      if (!this.authenticateConnect(req, clientSocket)) return;
      this.metrics.httpsTunnels++;
      this.handleHttpsRequest(req, clientSocket, head);
    });

    this.server.on('connection', (socket) => {
      this.connections.add(socket);
      socket.on('close', () => this.connections.delete(socket));
    });

    this.server.listen(this.port, '0.0.0.0', () => {
      console.log(`🚀 Proxy autenticado en puerto ${this.port}`);
      console.log(`👤 Usuario: ${this.username}`);
      console.log(`🔑 Password: ${this.password}`);
    });

    this.startResourceMonitoring();
  }

  handleStatusEndpoint(req, res) {
    const uptimeSec = Math.round((Date.now() - this.metrics.startTime) / 1000);
    const memUsage = process.memoryUsage();
    
    const status = {
      proxy: 'authenticated-http-https-proxy',
      port: this.port,
      uptime_seconds: uptimeSec,
      active_connections: this.connections.size,
      http_requests: this.metrics.httpRequests,
      https_tunnels: this.metrics.httpsTunnels,
      errors: this.metrics.errors,
      memory_mb: Math.round(memUsage.heapUsed / 1024 / 1024),
      timestamp: new Date().toISOString()
    };

    res.writeHead(200, { 
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    });
    res.end(JSON.stringify(status, null, 2));
  }

  authenticate(req, res) {
    const authHeader = req.headers['proxy-authorization'];
    if (!authHeader || !authHeader.startsWith('Basic ')) {
      this.sendAuthRequired(res);
      return false;
    }
    const credentials = authHeader.split(' ')[1];
    if (credentials !== this.validAuth) {
      this.sendAuthRequired(res);
      return false;
    }
    return true;
  }

  authenticateConnect(req, clientSocket) {
    const authHeader = req.headers['proxy-authorization'];
    if (!authHeader || !authHeader.startsWith('Basic ')) {
      clientSocket.write('HTTP/1.1 407 Proxy Authentication Required\r\n');
      clientSocket.write('Proxy-Authenticate: Basic realm="Proxy"\r\n');
      clientSocket.write('Content-Length: 0\r\n\r\n');
      clientSocket.end();
      return false;
    }
    const credentials = authHeader.split(' ')[1];
    if (credentials !== this.validAuth) {
      clientSocket.write('HTTP/1.1 407 Proxy Authentication Required\r\n');
      clientSocket.write('Proxy-Authenticate: Basic realm="Proxy"\r\n');
      clientSocket.write('Content-Length: 0\r\n\r\n');
      clientSocket.end();
      return false;
    }
    return true;
  }

  sendAuthRequired(res) {
    res.writeHead(407, {
      'Proxy-Authenticate': 'Basic realm="Proxy"',
      'Content-Type': 'text/plain'
    });
    res.end('Proxy Authentication Required');
  }

  handleHttpRequest(req, res) {
    const targetUrl = req.url;
    const parsedUrl = url.parse(targetUrl);
    this.log(`📡 HTTP ${req.method} ${targetUrl}`);

    delete req.headers['proxy-authorization'];

    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 80,
      path: parsedUrl.path,
      method: req.method,
      headers: req.headers,
      timeout: 30000
    };

    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });

    proxyReq.on('error', (err) => {
      this.metrics.errors++;
      this.log(`❌ Error HTTP: ${err.message}`);
      if (!res.headersSent) {
        res.writeHead(500);
        res.end('Proxy Error');
      }
    });

    proxyReq.on('timeout', () => {
      this.metrics.errors++;
      this.log('⏰ Timeout HTTP');
      proxyReq.destroy();
      if (!res.headersSent) {
        res.writeHead(504);
        res.end('Gateway Timeout');
      }
    });

    req.pipe(proxyReq);
  }

  handleHttpsRequest(req, clientSocket, head) {
    const [hostname, port] = req.url.split(':');
    this.log(`🔒 HTTPS CONNECT ${req.url}`);

    const serverSocket = net.connect(port || 443, hostname, () => {
      clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (head && head.length) serverSocket.write(head);
      serverSocket.pipe(clientSocket);
      clientSocket.pipe(serverSocket);
    });

    serverSocket.setTimeout(30000);
    clientSocket.setTimeout(30000);

    serverSocket.on('error', (err) => {
      this.metrics.errors++;
      this.log(`❌ Error HTTPS: ${err.message}`);
      clientSocket.destroy();
    });

    serverSocket.on('timeout', () => {
      this.metrics.errors++;
      this.log('⏰ Timeout HTTPS');
      serverSocket.destroy();
      clientSocket.destroy();
    });

    clientSocket.on('error', (err) => {
      this.log(`❌ Error cliente: ${err.message}`);
      serverSocket.destroy();
    });
  }

  startResourceMonitoring() {
    setInterval(() => {
      const memUsage = process.memoryUsage();
      const connections = this.connections.size;
      this.log(`📊 Memoria: ${Math.round(memUsage.heapUsed / 1024 / 1024)}MB | Conexiones: ${connections}`);
    }, 60000);
  }

  log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
  }

  stop() {
    if (this.server) {
      this.connections.forEach((s) => s.destroy());
      this.server.close();
      this.log('🛑 Proxy detenido');
    }
  }
}

const PORT = process.env.PROXY_PORT || 8080;
const USERNAME = process.env.PROXY_USER || 'admin';
const PASSWORD = process.env.PROXY_PASS || crypto.randomBytes(8).toString('hex');

const proxy = new AuthenticatedProxy(PORT, USERNAME, PASSWORD);
proxy.start();

process.on('SIGINT', () => { proxy.stop(); process.exit(0); });
process.on('SIGTERM', () => { proxy.stop(); process.exit(0); });
process.on('uncaughtException', (err) => {
  console.error('💥 Error no capturado:', err);
  proxy.stop();
  process.exit(1);
});
PROXYEOF

  sudo chown "$USER:$USER" /opt/proxy/proxy.js
}

setup_application() {
  print_info "Configurando aplicación Node..."
  create_proxy_file

  cat > /opt/proxy/package.json <<EOF
{
  "name": "authenticated-proxy",
  "version": "1.0.0",
  "description": "Proxy HTTP/HTTPS autenticado para AWS EC2",
  "main": "proxy.js",
  "scripts": {
    "start": "node proxy.js"
  }
}
EOF
}

create_systemd_service() {
  print_info "Creando servicio systemd para proxy..."
  sudo tee /etc/systemd/system/proxy.service > /dev/null <<EOF
[Unit]
Description=Authenticated Proxy Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/proxy
ExecStart=/usr/bin/node /opt/proxy/proxy.js
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production
Environment=PROXY_PORT=$PROXY_PORT
Environment=PROXY_USER=$PROXY_USER
Environment=PROXY_PASS=$PROXY_PASS
LimitNOFILE=4096
MemoryLimit=400M

[Install]
WantedBy=multi-user.target
EOF
}

start_proxy_service() {
  print_info "Iniciando servicio proxy..."
  sudo systemctl daemon-reload
  sudo systemctl enable proxy
  sudo systemctl start proxy
  sleep 3
  if sudo systemctl is-active --quiet proxy; then
    print_info "✅ Proxy iniciado correctamente"
  else
    print_error "❌ Error al iniciar proxy"
    sudo journalctl -u proxy -n 50 --no-pager
    exit 1
  fi
}

install_nginx() {
  print_info "Instalando Nginx..."
  if [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    sudo yum install -y nginx
  elif [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    sudo apt-get install -y nginx
  else
    print_warning "OS no soportado para instalación automática de Nginx"
    return
  fi
}

create_dashboard_html() {
  print_info "Creando dashboard profesional..."
  
  sudo mkdir -p /var/www/proxy-dashboard
  
  sudo tee /var/www/proxy-dashboard/index.html > /dev/null <<'HTMLEOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Proxy Server Dashboard</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --primary: #2563eb;
            --primary-dark: #1e40af;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --dark: #1f2937;
            --dark-light: #374151;
            --gray: #6b7280;
            --gray-light: #9ca3af;
            --bg: #0f172a;
            --bg-card: #1e293b;
            --text: #f1f5f9;
            --text-muted: #94a3b8;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        header {
            margin-bottom: 40px;
            text-align: center;
        }
        
        h1 {
            font-size: 2.5em;
            font-weight: 700;
            margin-bottom: 10px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .subtitle {
            color: var(--text-muted);
            font-size: 1.1em;
        }
        
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
            margin-top: 15px;
        }
        
        .status-online {
            background: rgba(16, 185, 129, 0.1);
            color: var(--success);
            border: 1px solid var(--success);
        }
        
        .status-offline {
            background: rgba(239, 68, 68, 0.1);
            color: var(--danger);
            border: 1px solid var(--danger);
        }
        
        .pulse {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: currentColor;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 24px;
            margin-bottom: 30px;
        }
        
        .card {
            background: var(--bg-card);
            border-radius: 16px;
            padding: 24px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        
        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--primary), var(--primary-dark));
            opacity: 0;
            transition: opacity 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-4px);
            border-color: rgba(255, 255, 255, 0.1);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
        }
        
        .card:hover::before {
            opacity: 1;
        }
        
        .card-icon {
            width: 48px;
            height: 48px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.5em;
            margin-bottom: 16px;
        }
        
        .icon-blue { background: rgba(37, 99, 235, 0.1); color: var(--primary); }
        .icon-green { background: rgba(16, 185, 129, 0.1); color: var(--success); }
        .icon-purple { background: rgba(139, 92, 246, 0.1); color: #8b5cf6; }
        .icon-orange { background: rgba(245, 158, 11, 0.1); color: var(--warning); }
        .icon-red { background: rgba(239, 68, 68, 0.1); color: var(--danger); }
        .icon-cyan { background: rgba(6, 182, 212, 0.1); color: #06b6d4; }
        
        .card-title {
            font-size: 0.85em;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 8px;
            font-weight: 600;
        }
        
        .card-value {
            font-size: 2.5em;
            font-weight: 700;
            color: var(--text);
            margin-bottom: 4px;
        }
        
        .card-subtitle {
            font-size: 0.9em;
            color: var(--gray-light);
        }
        
        .details-section {
            background: var(--bg-card);
            border-radius: 16px;
            padding: 32px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            margin-bottom: 30px;
        }
        
        .section-header {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 24px;
            padding-bottom: 16px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .section-header h2 {
            font-size: 1.5em;
            font-weight: 600;
        }
        
        .section-icon {
            width: 40px;
            height: 40px;
            border-radius: 10px;
            background: rgba(37, 99, 235, 0.1);
            color: var(--primary);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.2em;
        }
        
        .config-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .config-item {
            background: rgba(255, 255, 255, 0.02);
            padding: 20px;
            border-radius: 12px;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .config-label {
            font-size: 0.85em;
            color: var(--text-muted);
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .config-value {
            font-size: 1.1em;
            color: var(--text);
            font-weight: 600;
            font-family: 'Courier New', monospace;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .copy-btn {
            background: rgba(37, 99, 235, 0.1);
            border: 1px solid var(--primary);
            color: var(--primary);
            padding: 6px 12px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.85em;
            transition: all 0.2s ease;
        }
        
        .copy-btn:hover {
            background: var(--primary);
            color: white;
        }
        
        .instructions {
            background: var(--bg-card);
            border-radius: 16px;
            padding: 32px;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        
        .instructions ol {
            margin-left: 20px;
            margin-top: 20px;
        }
        
        .instructions li {
            margin-bottom: 16px;
            color: var(--text-muted);
            line-height: 1.8;
        }
        
        .instructions code {
            background: rgba(255, 255, 255, 0.05);
            padding: 2px 8px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            color: var(--primary);
            font-size: 0.9em;
        }
        
        .footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid rgba(255, 255, 255, 0.05);
            color: var(--text-muted);
            font-size: 0.9em;
        }
        
        .refresh-indicator {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            color: var(--text-muted);
            font-size: 0.9em;
        }
        
        .spinner {
            animation: spin 2s linear infinite;
        }
        
        @keyframes spin {
            100% { transform: rotate(360deg); }
        }
        
        .error-banner {
            background: rgba(239, 68, 68, 0.1);
            border: 1px solid var(--danger);
            color: var(--danger);
            padding: 16px 20px;
            border-radius: 12px;
            margin-bottom: 24px;
            display: none;
            align-items: center;
            gap: 12px;
        }
        
        .error-banner.show {
            display: flex;
        }
        
        @media (max-width: 768px) {
            h1 { font-size: 2em; }
            .grid { grid-template-columns: 1fr; }
            .config-grid { grid-template-columns: 1fr; }
            .card-value { font-size: 2em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1><i class="fas fa-network-wired"></i> Proxy Server Dashboard</h1>
            <p class="subtitle">Monitor y configuración en tiempo real</p>
            <div class="status-badge status-online" id="status-badge">
                <span class="pulse"></span>
                <span id="status-text">Conectando...</span>
            </div>
        </header>
        
        <div class="error-banner" id="error-banner">
            <i class="fas fa-exclamation-triangle"></i>
            <span>No se puede conectar con el servidor proxy</span>
        </div>
        
        <div class="grid">
            <div class="card">
                <div class="card-icon icon-green">
                    <i class="fas fa-plug"></i>
                </div>
                <div class="card-title">Conexiones Activas</div>
                <div class="card-value" id="connections">-</div>
                <div class="card-subtitle">En tiempo real</div>
            </div>
            
            <div class="card">
                <div class="card-icon icon-blue">
                    <i class="fas fa-globe"></i>
                </div>
                <div class="card-title">Peticiones HTTP</div>
                <div class="card-value" id="http-requests">-</div>
                <div class="card-subtitle">Total acumulado</div>
            </div>
            
            <div class="card">
                <div class="card-icon icon-purple">
                    <i class="fas fa-lock"></i>
                </div>
                <div class="card-title">Túneles HTTPS</div>
                <div class="card-value" id="https-tunnels">-</div>
                <div class="card-subtitle">Total acumulado</div>
            </div>
            
            <div class="card">
                <div class="card-icon icon-cyan">
                    <i class="fas fa-clock"></i>
                </div>
                <div class="card-title">Tiempo Activo</div>
                <div class="card-value" id="uptime">-</div>
                <div class="card-subtitle" id="uptime-detail">-</div>
            </div>
            
            <div class="card">
                <div class="card-icon icon-orange">
                    <i class="fas fa-memory"></i>
                </div>
                <div class="card-title">Memoria en Uso</div>
                <div class="card-value" id="memory">-</div>
                <div class="card-subtitle">MB</div>
            </div>
            
            <div class="card">
                <div class="card-icon icon-red">
                    <i class="fas fa-exclamation-circle"></i>
                </div>
                <div class="card-title">Errores</div>
                <div class="card-value" id="errors">-</div>
                <div class="card-subtitle">Total acumulado</div>
            </div>
        </div>
        
        <div class="details-section">
            <div class="section-header">
                <div class="section-icon">
                    <i class="fas fa-cog"></i>
                </div>
                <h2>Configuración del Proxy</h2>
            </div>
            
            <div class="config-grid">
                <div class="config-item">
                    <div class="config-label">Servidor Proxy</div>
                    <div class="config-value">
                        <span id="proxy-server">Cargando...</span>
                        <button class="copy-btn" onclick="copyToClipboard('proxy-server')">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                
                <div class="config-item">
                    <div class="config-label">Puerto</div>
                    <div class="config-value">
                        <span id="proxy-port">-</span>
                        <button class="copy-btn" onclick="copyToClipboard('proxy-port')">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                
                <div class="config-item">
                    <div class="config-label">Tipo de Proxy</div>
                    <div class="config-value">
                        <span>HTTP/HTTPS</span>
                    </div>
                </div>
                
                <div class="config-item">
                    <div class="config-label">Última Actualización</div>
                    <div class="config-value">
                        <span id="last-update">-</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="instructions">
            <div class="section-header">
                <div class="section-icon">
                    <i class="fab fa-chrome"></i>
                </div>
                <h2>Configurar en Chrome</h2>
            </div>
            
            <ol>
                <li>Abre Chrome y ve a <code>chrome://settings/</code></li>
                <li>Busca "Proxy" o ve a <strong>Sistema → Abrir la configuración de proxy del equipo</strong></li>
                <li>En Windows: <strong>Configuración de LAN → Usar servidor proxy</strong></li>
                <li>Ingresa:
                    <ul style="margin-top: 8px; margin-left: 20px;">
                        <li>Dirección: <code id="chrome-server">Cargando...</code></li>
                        <li>Puerto: <code id="chrome-port">-</code></li>
                    </ul>
                </li>
                <li>Marca <strong>"Usar este servidor proxy para todos los protocolos"</strong></li>
                <li>Guarda y reinicia Chrome</li>
                <li>Al navegar, Chrome te pedirá usuario y contraseña del proxy</li>
            </ol>
        </div>
        
        <div class="footer">
            <div class="refresh-indicator">
                <i class="fas fa-sync-alt spinner"></i>
                Actualización automática cada 3 segundos
            </div>
            <p style="margin-top: 10px;">Proxy Server Dashboard v1.0</p>
        </div>
    </div>

    <script>
        let proxyServerIP = '';
        
        function formatUptime(seconds) {
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            const secs = seconds % 60;
            
            if (days > 0) return `${days}d ${hours}h`;
            if (hours > 0) return `${hours}h ${minutes}m`;
            if (minutes > 0) return `${minutes}m`;
            return `${secs}s`;
        }
        
        function formatUptimeDetail(seconds) {
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            const secs = seconds % 60;
            
            return `${days}d ${hours}h ${minutes}m ${secs}s`;
        }
        
        function formatNumber(num) {
            return num.toLocaleString('es-ES');
        }
        
        function formatTimestamp(isoString) {
            const date = new Date(isoString);
            return date.toLocaleString('es-ES');
        }
        
        function copyToClipboard(elementId) {
            const text = document.getElementById(elementId).textContent;
            navigator.clipboard.writeText(text).then(() => {
                const btn = event.target.closest('.copy-btn');
                const originalHTML = btn.innerHTML;
                btn.innerHTML = '<i class="fas fa-check"></i>';
                setTimeout(() => {
                    btn.innerHTML = originalHTML;
                }, 2000);
            });
        }
        
        async function updateDashboard() {
            try {
                const response = await fetch('/proxy_status');
                if (!response.ok) throw new Error('Error al obtener datos');
                
                const data = await response.json();
                
                // Actualizar badge de estado
                const statusBadge = document.getElementById('status-badge');
                const statusText = document.getElementById('status-text');
                statusBadge.className = 'status-badge status-online';
                statusText.textContent = 'Online';
                
                // Ocultar banner de error
                document.getElementById('error-banner').classList.remove('show');
                
                // Actualizar métricas
                document.getElementById('connections').textContent = data.active_connections;
                document.getElementById('http-requests').textContent = formatNumber(data.http_requests);
                document.getElementById('https-tunnels').textContent = formatNumber(data.https_tunnels);
                document.getElementById('uptime').textContent = formatUptime(data.uptime_seconds);
                document.getElementById('uptime-detail').textContent = formatUptimeDetail(data.uptime_seconds);
                document.getElementById('memory').textContent = data.memory_mb;
                document.getElementById('errors').textContent = formatNumber(data.errors);
                
                // Actualizar configuración
                if (!proxyServerIP) {
                    proxyServerIP = window.location.hostname;
                    document.getElementById('proxy-server').textContent = proxyServerIP;
                    document.getElementById('chrome-server').textContent = proxyServerIP;
                }
                document.getElementById('proxy-port').textContent = data.port;
                document.getElementById('chrome-port').textContent = data.port;
                document.getElementById('last-update').textContent = new Date().toLocaleTimeString('es-ES');
                
            } catch (error) {
                console.error('Error:', error);
                
                // Actualizar badge de estado
                const statusBadge = document.getElementById('status-badge');
                const statusText = document.getElementById('status-text');
                statusBadge.className = 'status-badge status-offline';
                statusText.textContent = 'Offline';
                
                // Mostrar banner de error
                document.getElementById('error-banner').classList.add('show');
            }
        }
        
        // Actualizar inmediatamente y luego cada 3 segundos
        updateDashboard();
        setInterval(updateDashboard, 3000);
    </script>
</body>
</html>
HTMLEOF

  print_info "Dashboard HTML creado en /var/www/proxy-dashboard"
}

configure_nginx_with_dashboard() {
  print_info "Configurando Nginx con dashboard..."

  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    # Debian/Ubuntu
    sudo rm -f /etc/nginx/sites-enabled/*
    
    sudo tee /etc/nginx/sites-available/proxy-dashboard > /dev/null <<EOF
server {
    listen $NGINX_STATUS_PORT;
    server_name _;

    root /var/www/proxy-dashboard;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /proxy_status {
        proxy_pass http://127.0.0.1:$PROXY_PORT/status;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
        add_header Access-Control-Allow-Origin *;
    }

    location /nginx_status {
        stub_status;
        allow 0.0.0.0/0;
    }
}
EOF
    sudo ln -sf /etc/nginx/sites-available/proxy-dashboard /etc/nginx/sites-enabled/proxy-dashboard
    
  else
    # Amazon Linux / CentOS
    sudo rm -f /etc/nginx/conf.d/*
    
    sudo tee /etc/nginx/conf.d/proxy-dashboard.conf > /dev/null <<EOF
server {
    listen $NGINX_STATUS_PORT;
    server_name _;

    root /var/www/proxy-dashboard;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /proxy_status {
        proxy_pass http://127.0.0.1:$PROXY_PORT/status;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
        add_header Access-Control-Allow-Origin *;
    }

    location /nginx_status {
        stub_status;
        allow 0.0.0.0/0;
    }
}
EOF
  fi

  sudo nginx -t
  sudo systemctl enable nginx
  sudo systemctl restart nginx
  
  print_info "✅ Nginx configurado correctamente"
}

configure_firewall() {
  print_info "Configurando firewall local..."
  if command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --permanent --add-port=$PROXY_PORT/tcp 2>/dev/null || true
    sudo firewall-cmd --permanent --add-port=$NGINX_STATUS_PORT/tcp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
  elif command -v ufw &> /dev/null; then
    sudo ufw allow $PROXY_PORT/tcp || true
    sudo ufw allow $NGINX_STATUS_PORT/tcp || true
  else
    print_warning "No se detectó firewall local"
  fi
}

get_public_ip() {
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s ifconfig.me)
  [ -z "$PUBLIC_IP" ] && PUBLIC_IP="TU_IP_PUBLICA"
  echo "$PUBLIC_IP"
}

show_security_group_info() {
  echo ""
  echo "=========================================="
  echo "⚠️  CONFIGURACIÓN AWS SECURITY GROUP"
  echo "=========================================="
  echo ""
  print_warning "Configura el Security Group en AWS Console:"
  echo ""
  echo "Reglas de entrada (Inbound):"
  echo "  1. Custom TCP - Puerto $PROXY_PORT - Tu IP o 0.0.0.0/0"
  echo "  2. Custom TCP - Puerto $NGINX_STATUS_PORT - Tu IP o 0.0.0.0/0"
  echo "  3. SSH - Puerto 22 - Tu IP"
  echo ""
}

create_monitor_script() {
  cat > /opt/proxy/monitor.sh <<'EOF'
#!/bin/bash
echo "📊 Monitor del Proxy Server"
echo "============================"
echo ""
echo "🔹 Estado Proxy:"
sudo systemctl status proxy --no-pager | head -n 3
echo ""
echo "🔹 Estado Nginx:"
sudo systemctl status nginx --no-pager | head -n 3
echo ""
echo "🔹 Últimos logs proxy:"
sudo journalctl -u proxy -n 5 --no-pager
EOF
  chmod +x /opt/proxy/monitor.sh
  print_info "Script monitor creado: /opt/proxy/monitor.sh"
}

show_summary() {
  PUBLIC_IP=$(get_public_ip)
  
  echo ""
  echo "=========================================="
  echo "✅ INSTALACIÓN COMPLETADA"
  echo "=========================================="
  echo ""
  echo "📋 Credenciales Proxy:"
  echo "   IP:        $PUBLIC_IP"
  echo "   Puerto:    $PROXY_PORT"
  echo "   Usuario:   $PROXY_USER"
  echo "   Password:  $PROXY_PASS"
  echo ""
  echo "🌐 Dashboard Profesional:"
  echo "   URL: http://$PUBLIC_IP:$NGINX_STATUS_PORT"
  echo ""
  echo "📊 Endpoints API:"
  echo "   Proxy Status:  http://$PUBLIC_IP:$NGINX_STATUS_PORT/proxy_status"
  echo "   Nginx Status:  http://$PUBLIC_IP:$NGINX_STATUS_PORT/nginx_status"
  echo ""
  echo "🔧 Configuración Chrome:"
  echo "   Proxy: $PUBLIC_IP:$PROXY_PORT"
  echo "   Usuario: $PROXY_USER"
  echo "   Password: $PROXY_PASS"
  echo ""
  echo "📝 Comandos útiles:"
  echo "   Ver logs proxy:    sudo journalctl -u proxy -f"
  echo "   Ver logs nginx:    sudo journalctl -u nginx -f"
  echo "   Reiniciar proxy:   sudo systemctl restart proxy"
  echo "   Reiniciar nginx:   sudo systemctl restart nginx"
  echo "   Monitor:           /opt/proxy/monitor.sh"
  echo ""
  
  # Guardar info
  cat > /opt/proxy/info.txt <<EOF
Proxy Server - Información de Instalación
==========================================

Credenciales:
  IP Pública: $PUBLIC_IP
  Puerto Proxy: $PROXY_PORT
  Usuario: $PROXY_USER
  Password: $PROXY_PASS

Dashboard:
  URL: http://$PUBLIC_IP:$NGINX_STATUS_PORT

Instalado: $(date)
EOF
  
  print_info "Información guardada en /opt/proxy/info.txt"
}

main() {
  print_info "Iniciando instalación..."
  print_info "Usuario: $PROXY_USER | Password: $PROXY_PASS"
  print_info "Puerto Proxy: $PROXY_PORT | Puerto Dashboard: $NGINX_STATUS_PORT"
  echo ""
  
  detect_os
  install_nodejs
  setup_application
  create_systemd_service
  start_proxy_service
  install_nginx
  create_dashboard_html
  configure_nginx_with_dashboard
  configure_firewall
  create_monitor_script
  show_security_group_info
  show_summary
  
  echo ""
  print_info "🎉 ¡Instalación completada con éxito!"
  print_info "🌐 Accede al dashboard en: http://$(get_public_ip):$NGINX_STATUS_PORT"
}

main
