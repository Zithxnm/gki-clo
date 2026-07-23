#!/bin/bash
set -e
echo "[+] Setting up ReSukiSU (Pinned: b0b73beb24341b7029a866005e9578ab58aa2df7)..."
curl -fsSL "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/b0b73beb24341b7029a866005e9578ab58aa2df7/kernel/setup.sh" | bash -s b0b73beb24341b7029a866005e9578ab58aa2df7
