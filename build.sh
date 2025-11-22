set -e
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH=$HOME/.local/bin:$PATH
echo $PATH
/opt/render/.local/bin/uv tool install typ2docx -p 3.14t
