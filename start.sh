#!/bin/bash

# Graceful shutdown: kill all child processes on exit/interrupt
trap 'kill 0' EXIT SIGINT SIGTERM

# Kill any processes on ports 3000 and 8000 first (before anything else)
kill_port() {
    local port=$1
    # Try ss (Linux), then lsof (macOS/Linux), then fuser
    local pids=""
    if command -v ss &> /dev/null; then
        pids=$(ss -tlnp 2>/dev/null | grep ":$port " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | tr '\n' ' ')
    fi
    if [ -z "$pids" ] && command -v lsof &> /dev/null; then
        pids=$(lsof -ti:$port 2>/dev/null | tr '\n' ' ')
    fi
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null && echo "[*] Killed PID $pid on port $port"
        done
    elif command -v fuser &> /dev/null; then
        fuser -k $port/tcp 2>/dev/null && echo "[*] Killed process(es) on port $port"
    fi
}
for port in 3000 8000; do kill_port $port; done
sleep 2

echo "======================================================="
echo "   S H A D O W B R O K E R   -   macOS / Linux Start   "
echo "======================================================="
echo ""

# Check for Node.js
if ! command -v npm &> /dev/null; then
    echo "[!] ERROR: npm is not installed. Please install Node.js 18+ (https://nodejs.org/)"
    exit 1
fi
echo "[*] Found Node.js $(node --version)"

# Check for Python 3
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "[!] ERROR: Python is not installed."
    echo "[!] Install Python 3.10-3.12 from https://python.org"
    exit 1
fi

PYVER=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
echo "[*] Found Python $PYVER"
PY_MINOR=$(echo "$PYVER" | cut -d. -f2)
if [ "$PY_MINOR" -ge 13 ] 2>/dev/null; then
    echo "[!] WARNING: Python $PYVER detected. Some packages may fail to build."
    echo "[!] Recommended: Python 3.10, 3.11, or 3.12."
    echo ""
fi

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "[*] Setting up backend..."
cd "$SCRIPT_DIR/backend"
if [ ! -d "venv" ]; then
    echo "[*] Creating Python virtual environment..."
    $PYTHON_CMD -m venv venv
    if [ $? -ne 0 ]; then
        echo "[!] ERROR: Failed to create virtual environment."
        exit 1
    fi
fi

source venv/bin/activate
echo "[*] Installing Python dependencies (this may take a minute)..."
pip install -q -r requirements.txt
if [ $? -ne 0 ]; then
    echo ""
    echo "[!] ERROR: pip install failed. See errors above."
    echo "[!] If you see Rust/cargo errors, your Python version may be too new."
    echo "[!] Recommended: Python 3.10, 3.11, or 3.12."
    exit 1
fi
echo "[*] Backend dependencies OK."
deactivate
echo "[*] Installing backend Node.js dependencies..."
npm install --silent
echo "[*] Backend Node.js dependencies OK."

cd "$SCRIPT_DIR"

echo ""
echo "[*] Setting up frontend..."
cd "$SCRIPT_DIR/frontend"
if [ ! -d "node_modules" ]; then
    echo "[*] Installing frontend dependencies..."
    npm install
    if [ $? -ne 0 ]; then
        echo "[!] ERROR: npm install failed. See errors above."
        exit 1
    fi
fi
echo "[*] Frontend dependencies OK."

echo ""
echo "[*] Ensuring ports 3000 and 8000 are free..."
for port in 3000 8000; do kill_port $port; done
# Fallback: npx kill-port if native tools didn't work
if command -v npx &> /dev/null; then
    npx -y kill-port 3000 8000 2>/dev/null || true
fi
sleep 2

echo ""
echo "======================================================="
echo "  Starting services...                                 "
echo "  Dashboard: http://localhost:3000 (LAN: use your machine's IP) "
echo "  Keep this window open! Initial load takes ~10s.      "
echo "======================================================="
echo "  (Press Ctrl+C to stop)"
echo ""

npm run dev
