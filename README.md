# Dotfiles & Dev Setup

`install.sh` should be the only thing you need.

```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

Follow the instructions in the prompt.

---

## Bare Linux Install / Containers

On a fresh or blank Linux install (Ubuntu, Debian, Fedora, or container), make sure `curl` and `sudo` are installed first:

### Ubuntu / Debian
```bash
apt-get update && apt-get install -y curl sudo
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

### Fedora
```bash
dnf install -y curl sudo
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```
