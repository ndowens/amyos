#!/usr/bin/bash
set -euo pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

# Workaround to allow installing nix with composefs
mkdir /nix

# RPM packages list
declare -A RPM_PACKAGES=(
  ["fedora"]="\
    aria2 \
    bchunk \
    fuse-btfs \
    fuse-devel \
    fuse3-devel \
    fzf \
    gparted \
    gwenview \
    hashcat \
    keepassxc \
    kcalc \
    ksystemlog \
    neovim \
    qemu-kvm \
    thefuck \
    util-linux \
    virt-manager \
    virt-viewer \
    yt-dlp \
    zsh-autosuggestions \
    zsh"

  ["terra"]="\
    hack-nerd-fonts \
    ubuntu-nerd-fonts \
    ubuntumono-nerd-fonts \
    ubuntusans-nerd-fonts"


  ["fedora-multimedia"]="\
    mpv" 

  ["docker-ce"]="\
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin"

  ["brave-browser"]="brave-browser"
  ["cloudflare-warp"]="cloudflare-warp"
  ["copr:sneexy/zen-browser"]="zen-browser"
  ["copr:bieszczaders/kernel-cachyos-lto"]="kernel-cachyos-lto"
)

log "Starting Amy OS build process"

dnf5 -y remove kernel kernel-modules

log "Installing RPM packages"
mkdir -p /var/opt
for repo in "${!RPM_PACKAGES[@]}"; do
  read -ra pkg_array <<<"${RPM_PACKAGES[$repo]}"
  if [[ $repo == copr:* ]]; then
    # Handle COPR packages
    copr_repo=${repo#copr:}
    dnf5 -y copr enable "$copr_repo"
    dnf5 -y install "${pkg_array[@]}"
    dnf5 -y copr disable "$copr_repo"
  else
    # Handle regular packages
    [[ $repo != "fedora" ]] && enable_opt="--enable-repo=$repo" || enable_opt=""
    cmd=(dnf5 -y install)
    [[ -n "$enable_opt" ]] && cmd+=("$enable_opt")
    cmd+=("${pkg_array[@]}")
    "${cmd[@]}"
  fi
done

log "Enabling system services"
systemctl enable podman.service libvirtd.service

log "Installing Cursor GUI"
GUI_DIR="/tmp/cursor-gui"
mkdir -p "$GUI_DIR"
DOWNLOAD_URL=$(curl -s "https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable" | grep -o '"downloadUrl":"[^"]*' | cut -d'"' -f4)
if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Failed to extract download URL from JSON response"
  exit 1
fi
aria2c --dir="$GUI_DIR" --out="cursor.appimage" --max-tries=3 --connect-timeout=30 "$DOWNLOAD_URL"
chmod +x "$GUI_DIR/cursor.appimage"
(cd "$GUI_DIR" && ./cursor.appimage --appimage-extract)
chmod -R a+rX "$GUI_DIR/squashfs-root"
cp -r "$GUI_DIR/squashfs-root/usr/share/icons/"* /usr/share/icons
mkdir -p /usr/share/cursor/bin
cp -r "$GUI_DIR/squashfs-root/usr/share/cursor/"* /usr/share/cursor
install -m 0755 /usr/share/cursor/resources/linux/bin/cursor /usr/share/cursor/bin/cursor
ln -s /usr/share/cursor/bin/cursor /usr/bin/cursor

log "Installing Cursor CLI"
CLI_DIR="/tmp/cursor-cli"
mkdir -p "$CLI_DIR"
aria2c --dir="$CLI_DIR" --out="cursor-cli.tar.gz" --max-tries=3 --connect-timeout=30 "https://api2.cursor.sh/updates/download-latest?os=cli-alpine-x64"
tar -xzf "$CLI_DIR/cursor-cli.tar.gz" -C "$CLI_DIR"
install -m 0755 "$CLI_DIR/cursor" /usr/share/cursor/bin/cursor-tunnel
ln -s /usr/share/cursor/bin/cursor-tunnel /usr/bin/cursor-cli
ln -s /usr/share/cursor/bin/cursor-tunnel /usr/share/cursor/bin/code-tunnel

log "Adding Amy OS just recipes"
echo "import \"/usr/share/amyos/just/amy.just\"" >>/usr/share/ublue-os/justfile

log "Hide incompatible Bazzite just recipes"
for recipe in "install-coolercontrol" "install-openrgb"; do
  if ! grep -l "^$recipe:" /usr/share/ublue-os/just/*.just | grep -q .; then
    echo "Error: Recipe $recipe not found in any just file"
    exit 1
  fi
  sed -i "s/^$recipe:/_$recipe:/" /usr/share/ublue-os/just/*.just
done

log "Build process completed"
