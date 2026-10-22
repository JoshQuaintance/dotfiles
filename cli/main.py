"""`dot` CLI entry point: argument parsing and subcommand dispatch."""

import argparse
import sys

from cli.backup import run_backup, run_restore
from cli.bench import run_bench
from cli.clean import run_clean
from cli.doctor import run_doctor
from cli.env_audit import run_env_audit
from cli.lint_help import run_lint_help
from cli.new_fn import run_new_fn
from cli.profile import run_profile
from cli.prompt import run_prompt_command
from cli.prune import run_prune
from cli.status import run_status
from cli.sync import run_sync
from cli.test import run_tests
from cli.update import run_update


def build_parser() -> argparse.ArgumentParser:
    """Construct the CLI argument parser and all subcommand definitions."""
    parser = argparse.ArgumentParser(
        prog="dot",
        description="Unified developer workstation manager for dotfiles, health diagnostics, and tests.",
    )
    subparsers = parser.add_subparsers(dest="subcommand", help="Available subcommands")

    # 1. Overview & Diagnostics (status, doctor, env, test, bench)
    parser_status = subparsers.add_parser(
        "status",
        help="Show quick 1-screen workstation & dotfiles status overview",
    )
    parser_status.add_argument("-j", "--json", action="store_true", help="Output workstation status as JSON")

    parser_doctor = subparsers.add_parser(
        "doctor",
        aliases=["health"],
        help="Run system health checks and audit symlinks",
    )
    parser_doctor.add_argument("-f", "--fix", action="store_true", help="Automatically repair broken or missing symlinks")
    parser_doctor.add_argument("--strict", action="store_true", help="Exit 2 when warnings are present (with 0 failures)")
    parser_doctor.add_argument("-j", "--json", action="store_true", help="Output health check report as JSON")

    parser_env = subparsers.add_parser(
        "env",
        help="Audit environment variables, $PATH precedence, and shadowed binaries",
    )
    parser_env.add_argument("-a", "--all", action="store_true", help="Show all $PATH entries without truncation")
    parser_env.add_argument("-j", "--json", action="store_true", help="Output environment audit as JSON")

    subparsers.add_parser(
        "test",
        help="Run deep runtime configuration and schema integration tests",
    )

    parser_bench = subparsers.add_parser(
        "bench",
        help="Benchmark interactive Zsh startup latency and per-phase breakdown",
    )
    parser_bench.add_argument("-n", "--iterations", type=int, default=5, help="Number of benchmark runs (default: 5)")
    parser_bench.add_argument("-p", "--prompt", action="store_true", help="Also benchmark shell prompt rendering (Native vs Spaceship)")
    parser_bench.add_argument("-t", "--tools", action="store_true", help="Also benchmark modern CLI tools (rg, fd, eza)")
    parser_bench.add_argument("-a", "--all", action="store_true", help="Run full benchmark suite (startup + tools + prompt)")
    parser_bench.add_argument("-s", "--save", action="store_true", help="Save benchmark results as performance baseline")
    parser_bench.add_argument("-c", "--compare", action="store_true", help="Compare startup latency against saved baseline")
    parser_bench.add_argument("--trend", action="store_true", help="Render saved benchmark history as a sparkline and flag regressions")
    parser_bench.add_argument("-j", "--json", action="store_true", help="Output startup benchmark results as JSON")

    # 2. Synchronization, Updates & Symlinks (sync, update, link, prompt)
    parser_sync = subparsers.add_parser(
        "sync",
        help="Two-way dotfiles Git synchronization across machines",
    )
    parser_sync.add_argument("-m", "--message", help="Custom Git commit message")
    parser_sync.add_argument("-n", "--dry-run", action="store_true", help="Preview changes without committing or pushing")
    parser_sync.add_argument("--no-push", action="store_true", help="Commit and pull without pushing to remote")

    parser_update = subparsers.add_parser(
        "update",
        help="Check and apply dotfiles, Homebrew, and Mise updates",
    )
    parser_update.add_argument("-c", "--check", action="store_true", help="Check for updates without applying")
    parser_update.add_argument("-d", "--diff", action="store_true", help="Preview incoming diff without applying updates")
    parser_update.add_argument("-y", "--yes", action="store_true", help="Automatically apply updates without prompting")
    parser_update.add_argument("-a", "--all", action="store_true", help="Full workstation upgrade: git + Homebrew + Mise + test")
    parser_update.add_argument("-t", "--tools", action="store_true", help="Update Homebrew and Mise tools only")
    parser_update.add_argument("--test", action="store_true", help="Run deep integration tests after update")
    parser_update.add_argument("--no-prune", action="store_true", help="Keep links, caches and packages removed upstream")

    parser_link = subparsers.add_parser(
        "link",
        help="Audit or auto-heal declarative symlinks",
    )
    parser_link.add_argument("-f", "--fix", action="store_true", help="Automatically create or re-point symlinks")

    parser_prompt = subparsers.add_parser(
        "prompt",
        help="Benchmark and select shell prompt (native, spaceship)",
    )
    parser_prompt.add_argument("action", nargs="?", choices=["set", "benchmark"], help="Prompt action ('set' or 'benchmark')")
    parser_prompt.add_argument("engine", nargs="?", help="Prompt engine to set ('native', 'spaceship')")

    # 3. Hygiene, Pruning & Local State Backups (clean, prune, backup, restore)
    _add_maintenance_subparsers(subparsers)

    return parser


def _add_maintenance_subparsers(subparsers: argparse._SubParsersAction) -> None:
    """Register hygiene, pruning, and snapshot backup/restore subcommands."""
    parser_clean = subparsers.add_parser(
        "clean",
        help="Clean stale Zsh dumps, completion caches, oversized logs, and temp files",
    )
    parser_clean.add_argument("-n", "--dry-run", action="store_true", help="Preview items and space to be reclaimed without deleting")
    parser_clean.add_argument("-a", "--all", action="store_true", help="Also remove legacy ~/.oh-my-zsh and prune uv/Homebrew caches")
    parser_clean.add_argument("-b", "--builds", action="store_true", help="Clean stale build directories (target, .next, .turbo, dist, .angular) inactive >30 days")

    parser_prune = subparsers.add_parser(
        "prune",
        help="Remove links, caches and packages deleted from the dotfiles since a commit",
    )
    parser_prune.add_argument("ref", nargs="?", help="Commit to compare against HEAD (default: ORIG_HEAD, the commit before the last pull)")
    parser_prune.add_argument("-n", "--dry-run", action="store_true", help="Preview what would be removed without deleting")
    parser_prune.add_argument("-o", "--orphans", action="store_true", help="Also offer to uninstall brew packages and mise versions the dotfiles don't declare")

    parser_backup = subparsers.add_parser(
        "backup",
        help="Snapshot untracked local machine overrides, scratchpads, and state",
    )
    parser_backup.add_argument("-o", "--output", help="Custom output .tar.gz path")
    parser_backup.add_argument("-n", "--dry-run", action="store_true", help="Preview files to back up without writing archive")
    parser_backup.add_argument("-l", "--list", action="store_true", help="List existing backup archives")

    parser_restore = subparsers.add_parser(
        "restore",
        help="Restore untracked local machine overrides and state from a backup snapshot",
    )
    parser_restore.add_argument("archive", nargs="?", help="Backup archive path (default: most recent archive)")
    parser_restore.add_argument("-n", "--dry-run", action="store_true", help="Preview files that would be restored without extracting")

    parser_profile = subparsers.add_parser(
        "profile",
        help="Profile Zsh startup functions using zsh/zprof",
    )
    parser_profile.add_argument("-n", "--top", type=int, default=15, help="Number of top functions to display (default: 15)")
    parser_profile.add_argument("-j", "--json", action="store_true", help="Output profiler results as JSON")

    parser_new_fn = subparsers.add_parser(
        "new-fn",
        help="Scaffold a new Zsh function with header doc, --help guard, and test stub",
    )
    parser_new_fn.add_argument("name", help="Name of the new Zsh function")
    parser_new_fn.add_argument("-m", "--module", default="custom", help="Target module in zsh/functions/<module>.zsh")
    parser_new_fn.add_argument("-d", "--desc", default="", help="One-line function description")

    parser_lint_help = subparsers.add_parser(
        "lint-help",
        help="Audit Zsh function doc headers, --help exit-0, and <=120 line bounds",
    )
    parser_lint_help.add_argument("-j", "--json", action="store_true", help="Output audit results as JSON")


def _dispatch_command(args: argparse.Namespace) -> int:
    """Dispatch parsed CLI arguments to the corresponding subcommand runner."""
    cmd = args.subcommand or "status"
    handlers = {
        "status": lambda a: run_status(json_output=getattr(a, "json", False)),
        "doctor": lambda a: run_doctor(
            fix=a.fix,
            json_output=getattr(a, "json", False),
            strict=getattr(a, "strict", False),
        ),
        "health": lambda a: run_doctor(
            fix=a.fix,
            json_output=getattr(a, "json", False),
            strict=getattr(a, "strict", False),
        ),
        "link": lambda a: run_doctor(fix=a.fix),
        "env": lambda a: run_env_audit(show_all_path=a.all, json_output=getattr(a, "json", False)),
        "test": lambda _a: run_tests(),
        "prompt": lambda a: run_prompt_command(subcommand=a.action, value=a.engine),
        "profile": lambda a: run_profile(top_n=a.top, json_output=getattr(a, "json", False)),
        "new-fn": lambda a: run_new_fn(name=a.name, module=a.module, desc=a.desc),
        "lint-help": lambda a: run_lint_help(json_output=getattr(a, "json", False)),
        "bench": lambda a: run_bench(
            iterations=a.iterations,
            test_prompt=a.prompt,
            test_tools=a.tools,
            test_all=a.all,
            json_output=getattr(a, "json", False),
            save_baseline=getattr(a, "save", False),
            compare_baseline=getattr(a, "compare", False),
            show_trend=getattr(a, "trend", False),
        ),
        "sync": lambda a: run_sync(
            message=a.message,
            dry_run=a.dry_run,
            auto_push=not a.no_push,
        ),
        "clean": lambda a: run_clean(dry_run=a.dry_run, clean_all=a.all, clean_builds=a.builds),
        "prune": lambda a: run_prune(ref=a.ref, dry_run=a.dry_run, orphans=a.orphans),
        "update": lambda a: run_update(
            check_only=a.check,
            auto_apply=a.yes,
            update_all=a.all,
            tools_only=a.tools,
            test_after=a.test,
            prune=not a.no_prune,
            show_diff=getattr(a, "diff", False),
        ),
        "backup": lambda a: run_backup(output_path=a.output, dry_run=a.dry_run, list_only=a.list),
        "restore": lambda a: run_restore(archive_path=a.archive, dry_run=a.dry_run),
    }
    handler = handlers.get(cmd, lambda _a: run_status())
    return handler(args)


def main() -> None:
    """Entry point for the `dot` workstation CLI."""
    parser = build_parser()
    args = parser.parse_args()
    sys.exit(_dispatch_command(args))


if __name__ == "__main__":
    main()
