# Dotfiles & Dev Setup

`install.sh` should be the only thing you need.

```bash
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

Follow the instructions in the prompt.

---

## Bare Linux Install

On a fresh or minimal Linux install (Ubuntu, Debian, Fedora, or container), make sure `curl` is installed first:

### Ubuntu / Debian
```bash
sudo apt update && sudo apt install -y curl
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```

### Fedora
```bash
sudo dnf install -y curl
curl -fsSL https://raw.githubusercontent.com/JoshQuaintance/dotfiles/main/install.sh | bash
```
