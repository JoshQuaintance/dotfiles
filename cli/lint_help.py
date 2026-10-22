"""`dot lint-help`: fast audit of Zsh function headers, `--help` exit-0, and 120-line bounds."""

import contextlib
import io
import json

from cli.manifest import get_dotfiles_dir
from cli.test import (
    TestReport,
    _check_commands_documentation,
    _check_function_headers_and_help,
    _check_zsh_function_bounds,
)
from cli.ui import C_BOLD, C_GREEN, C_RED, C_RESET, C_YELLOW, print_header


def run_lint_help(json_output: bool = False) -> int:
    """Run the fast function bounds, header doc, and `--help` audit."""
    dotfiles = get_dotfiles_dir()
    report = TestReport()

    if json_output:
        with contextlib.redirect_stdout(io.StringIO()):
            _check_zsh_function_bounds(report, dotfiles)
            _check_function_headers_and_help(report, dotfiles)
            _check_commands_documentation(report, dotfiles)
        payload = {
            "passed": report.passed,
            "warnings": report.warnings,
            "failed": report.failed,
        }
        print(json.dumps(payload, indent=2))
        return 1 if report.failed > 0 else 0

    print_header("Dotfiles Function Help, Header & Bounds Linter")
    print(f"\n{C_BOLD}Function Contracts{C_RESET}")
    _check_zsh_function_bounds(report, dotfiles)
    _check_function_headers_and_help(report, dotfiles)
    _check_commands_documentation(report, dotfiles)

    print(
        f"\n{C_BOLD}Summary:{C_RESET} {C_GREEN}{report.passed} passed{C_RESET}, "
        f"{C_YELLOW}{report.warnings} warnings{C_RESET}, "
        f"{C_RED}{report.failed} failed{C_RESET}\n"
    )
    return 1 if report.failed > 0 else 0
