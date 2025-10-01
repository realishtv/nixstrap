#!/usr/bin/env bash
# This script is designed to be run from a NixOS installer environment.
# It guides a user through the process of setting up a server to be managed
# by a private, declarative NixOS configuration repository on GitHub.

set -e # Exit immediately if any command fails.

# --- Helper Functions for Color and Style ---
info() { echo -e "\e[34m\e[1m[INFO]\e[0m $1"; }
prompt() { read -p $'\e[32m\e[1m[PROMPT]\e[0m '"$1" "$2"; }
wait_for_user() { read -p $'\e[32m\e[1m[PROMPT]\e[0m '"$1"; }
warn() { echo -e "\e[33m\e[1m[WARN]\e[0m $1"; }
success() { echo -e "\e[32m\e[1m[SUCCESS]\e[0m $1"; }
fail() { echo -e "\e[31m\e[1m[FAIL]\e[0m $1"; exit 1; }

# --- Main Script ---
info "Welcome to the interactive NixOS GitOps Bootstrapper!"
info "This script will guide you through setting up this server to be managed by your private configuration repository."

# 1. Get GitHub details from the user
while true; do
  prompt "Please enter your GitHub repository (e.g., username/repo): " GH_SLUG
  if [[ "$GH_SLUG" =~ ^[^/]+/[^/]+$ ]]; then
    GH_USER=$(echo "$GH_SLUG" | cut -d'/' -f1)
    GH_REPO=$(echo "$GH_SLUG" | cut -d'/' -f2)
    break
  else
    warn "Invalid format. Please use the format 'username/repo'."
  fi
done

# Construct the SSH URL from the user's input
REPO_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
info "Using repository URL: $REPO_URL"

# 2. Generate the Deploy Key (Idempotently)
KEY_DIR="$HOME/.ssh"
KEY_PATH="$KEY_DIR/bootstrap_deploy_key"
mkdir -p "$KEY_DIR"

if [ -f "$KEY_PATH" ]; then
  info "Reusing existing deploy key found at $KEY_PATH"
else
  info "Generating a new read-only deploy key..."
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "nixos-bootstrap-key" >/dev/null
  success "New deploy key generated at $KEY_PATH"
fi

# 3. Display the Public Key, a Direct Link, and Wait for the User
info "Please add the following public key to your GitHub repository's Deploy Keys."
warn "IMPORTANT: Do NOT check 'Allow write access'. This key should be read-only."

WEB_URL_BASE="https://github.com/${GH_USER}/${GH_REPO}"
DEPLOY_KEY_URL="${WEB_URL_BASE}/settings/keys"

echo ""
info "Click this link to go directly to the Deploy Keys page:"
echo -e "\e[32m\e[4m${DEPLOY_KEY_URL}\e[0m"
echo ""
echo -e "\e[33m"
echo "--- COPY THE KEY BELOW AND PASTE IT ON THAT PAGE ---"
cat "${KEY_PATH}.pub"
echo "--- END OF KEY ---"
echo -e "\e[0m"

wait_for_user "Press [Enter] after you have added and saved the key on GitHub..."

# 4. Test the Connection Until It Works
info "Testing connection to GitHub... (This may take a moment)"
while ! GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" git ls-remote "$REPO_URL" &>/dev/null; do
  warn "Connection failed. Please ensure you have correctly added the key and saved it."
  wait_for_user "Press [Enter] to try again..."
done
success "Connection successful!"

# 5. The Pivot: Clone and Prepare for Rebuild
info "Cloning your real configuration to a temporary location..."
CLONE_DIR="/tmp/real-config"
# FIX: Use sudo to ensure we can clean up the old directory
sudo rm -rf "$CLONE_DIR"
GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
git clone "$REPO_URL" "$CLONE_DIR"

# 5.5. PERSIST THE BOOTSTRAP KEY FOR THE FINAL SYSTEM
info "Placing the permanent deploy key onto the persistent storage..."
PERSIST_SECRETS_DIR="/mnt/persist/secrets"
FINAL_KEY_PATH="$PERSIST_SECRETS_DIR/deploy_key"
sudo mkdir -p "$PERSIST_SECRETS_DIR"
sudo cp "$KEY_PATH" "$FINAL_KEY_PATH"
sudo chmod 600 "$FINAL_KEY_PATH"
success "Permanent deploy key has been securely stored for the new system."

# 6. Discover Hostname and Run Final Build
info "Discovering hostname for the build from your configuration..."
HOSTNAME=$(cat "$CLONE_DIR/configuration.nix" | grep "networking.hostName" | cut -d '"' -f 2)
if [ -z "$HOSTNAME" ]; then
    fail "Could not automatically determine hostname from your configuration.nix. Aborting."
fi
info "Found hostname: $HOSTNAME"

info "Pivoting to your real configuration. This will now build your final system. This may take a while..."
info "The command being run is: sudo nixos-rebuild switch --flake $CLONE_DIR#$HOSTNAME"

if sudo nixos-rebuild switch --flake "$CLONE_DIR#$HOSTNAME"; then
  success "Bootstrap complete! Your system is now managed by your private repository."
  info "The automation service (e.g., deploy-rs) defined in your repository will now take over."
  info "This temporary bootstrap script and its key have served their purpose."
  rm -f "${KEY_PATH}" "${KEY_PATH}.pub"
else
  fail "The final build failed. The system has not been changed."
  fail "Please check the errors above. Your real configuration may have a problem."
fi

