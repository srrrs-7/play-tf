#!/bin/bash
set -e

echo "🚀 Starting Dev Container setup..."

echo "👤 Current user:"
whoami

# alias terraform to tf
alias tf="terraform" >> ~/.bashrc
source ~/.bashrc

# install gemini cli
npm install -g @google/gemini-cli

# init and execute personal setup script
if [ ! -f ".devcontainer/setup.personal.sh" ]; then
  cat << 'EOF' > .devcontainer/setup.personal.sh
#!/bin/bash
set -e

# Your personal setup steps here
EOF
  chmod +x .devcontainer/setup.personal.sh
fi
echo "🔧 Running personal setup..."
bash .devcontainer/setup.personal.sh

echo "✨ Dev Container setup completed successfully!"