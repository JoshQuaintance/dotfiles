"""`dot new-fn`: scaffold a new custom Zsh function, registry entry, and unit test stub."""

import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

from cli.manifest import get_dotfiles_dir
from cli.ui import C_GREEN, C_RED, C_RESET, ICON_FAIL, ICON_OK

VALID_FN_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_-]*$")
VALID_MOD_RE = re.compile(r"^[a-zA-Z0-9_-]+$")


def _validate_new_fn(name: str, mod_clean: str, root: Path) -> Optional[str]:
    """Return an error string if `name` or `mod_clean` cannot be scaffolded, else None."""
    if not VALID_FN_RE.match(name) or not VALID_MOD_RE.match(mod_clean):
        return f"Invalid function or module name: '{name}' / '{mod_clean}'"

    functions_zsh = root / "zsh" / "functions.zsh"
    if not functions_zsh.is_file():
        return f"Registry file not found: {functions_zsh}"

    reg_text = functions_zsh.read_text(encoding="utf-8")
    fn_block_m = re.search(r"(typeset\s+-ga\s+DOTFILES_FUNCTIONS=\s*\([\s\S]*?)(\n\))", reg_text)
    if not fn_block_m:
        return "Could not locate DOTFILES_FUNCTIONS in zsh/functions.zsh"

    existing_tokens = [
        tok
        for line in fn_block_m.group(1).splitlines()[1:]
        for tok in line.split("#", 1)[0].split()
    ]
    if name in existing_tokens:
        return f"Function '{name}' is already registered in DOTFILES_FUNCTIONS"

    func_dir = root / "zsh" / "functions"
    for zfile in func_dir.glob("*.zsh"):
        if re.search(rf"^{re.escape(name)}\(\)\s*\{{", zfile.read_text(encoding="utf-8"), re.MULTILINE):
            return f"Function '{name}' already exists in {zfile.name}"
    return None


def scaffold_new_function(
    name: str,
    module: str = "custom",
    desc: str = "",
    dotfiles: Optional[Path] = None,
    regen_docs: bool = True,
) -> tuple[bool, str]:
    """Scaffold a new Zsh function, register it in DOTFILES_FUNCTIONS, and create a test stub."""
    root = dotfiles or get_dotfiles_dir()
    mod_clean = module.removesuffix(".zsh")
    err = _validate_new_fn(name, mod_clean, root)
    if err:
        return False, err

    functions_zsh = root / "zsh" / "functions.zsh"
    reg_text = functions_zsh.read_text(encoding="utf-8")
    fn_block_m = re.search(r"(typeset\s+-ga\s+DOTFILES_FUNCTIONS=\s*\([\s\S]*?)(\n\))", reg_text)
    assert fn_block_m is not None

    func_dir = root / "zsh" / "functions"
    func_dir.mkdir(parents=True, exist_ok=True)

    summary = desc.strip() or f"Custom {name} utility"
    target_mod = func_dir / f"{mod_clean}.zsh"
    stub = (
        f"\n# {summary} ({name})\n"
        f"{name}() {{\n"
        f'  if [[ "$1" == "-h" || "$1" == "--help" ]]; then\n'
        f'    printf "Usage: {name}\\n"\n'
        f"    return 0\n"
        f"  fi\n"
        f"}}\n"
    )
    existing_mod = target_mod.read_text(encoding="utf-8") if target_mod.exists() else ""
    target_mod.write_text(existing_mod.rstrip() + "\n" + stub.lstrip("\n"), encoding="utf-8")

    updated_reg = (
        reg_text[: fn_block_m.start(2)]
        + f"\n  {name}"
        + reg_text[fn_block_m.start(2) :]
    )
    functions_zsh.write_text(updated_reg, encoding="utf-8")

    test_dir = root / "tests" / "zsh"
    test_dir.mkdir(parents=True, exist_ok=True)
    test_file = test_dir / f"test_{mod_clean}.zsh"
    safe_test_id = name.replace("-", "_")
    test_header = "" if test_file.exists() else 'source "$DOTFILES_DIR/zsh/functions.zsh"\n'
    test_stub = (
        f"{test_header}\n"
        f"test_{safe_test_id}_help_returns_zero() {{\n"
        f"  local out\n"
        f'  out="$({name} --help)" || fail "{name} --help failed"\n'
        f'  assert_contains "$out" "Usage: {name}"\n'
        f"}}\n"
    )
    prev_test = test_file.read_text(encoding="utf-8") if test_file.exists() else ""
    test_file.write_text((prev_test.rstrip() + "\n" + test_stub).lstrip("\n"), encoding="utf-8")

    gen_docs = root / "libexec" / "gen_docs.py"
    if regen_docs and gen_docs.is_file():
        subprocess.run([sys.executable, str(gen_docs)], cwd=root, capture_output=True, check=False)

    return True, f"Scaffolded '{name}' in zsh/functions/{mod_clean}.zsh and tests/zsh/test_{mod_clean}.zsh"


def run_new_fn(name: str, module: str = "custom", desc: str = "") -> int:
    """CLI entrypoint for `dot new-fn`."""
    ok, msg = scaffold_new_function(name=name, module=module, desc=desc)
    if ok:
        print(f"{C_GREEN}{ICON_OK} {msg}{C_RESET}")
        return 0
    print(f"{C_RED}{ICON_FAIL} {msg}{C_RESET}")
    return 1
