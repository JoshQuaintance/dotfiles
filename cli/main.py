import argparse
import sys

from cli.bench import run_bench
from cli.clean import run_clean
from cli.doctor import run_doctor
from cli.prune import run_prune
from cli.status import run_status
from cli.test import run_tests
from cli.update import run_update


def main():
    parser = argparse.ArgumentParser(
        prog="dot",
        description="Unified developer workstation manager for dotfiles, health diagnostics, and tests.",
    )
    subparsers = parser.add_subparsers(dest="subcommand", help="Available subcommands")

    # dot status
    subparsers.add_parser("status", help="Show quick 1-screen workstation & dotfiles status overview")

    # dot doctor
    parser_doctor = subparsers.add_parser("doctor", help="Run system health checks and audit symlinks")
    parser_doctor.add_argument("-f", "--fix", action="store_true", help="Automatically repair broken or missing symlinks")

    # dot test
    subparsers.add_parser("test", help="Run deep runtime configuration and schema integration tests")

    # dot bench
    parser_bench = subparsers.add_parser("bench", help="Benchmark interactive Zsh startup latency and per-phase breakdown")
    parser_bench.add_argument("-n", "--iterations", type=int, default=5, help="Number of benchmark runs (default: 5)")

    # dot clean
    parser_clean = subparsers.add_parser("clean", help="Clean stale Zsh dumps, completion caches, oversized logs, and temp files")
    parser_clean.add_argument("-n", "--dry-run", action="store_true", help="Preview items and space to be reclaimed without deleting")
    parser_clean.add_argument("-a", "--all", action="store_true", help="Also remove legacy ~/.oh-my-zsh and prune uv/Homebrew caches")

    # dot prune
    parser_prune = subparsers.add_parser("prune", help="Remove links, caches and packages deleted from the dotfiles since a commit")
    parser_prune.add_argument("ref", nargs="?", help="Commit to compare against HEAD (default: ORIG_HEAD, the commit before the last pull)")
    parser_prune.add_argument("-n", "--dry-run", action="store_true", help="Preview what would be removed without deleting")
    parser_prune.add_argument("-o", "--orphans", action="store_true", help="Also offer to uninstall brew packages and mise versions the dotfiles don't declare")

    # dot update
    parser_update = subparsers.add_parser("update", help="Check and apply dotfiles, Homebrew, and Mise updates")
    parser_update.add_argument("-c", "--check", action="store_true", help="Check for updates without applying")
    parser_update.add_argument("-y", "--yes", action="store_true", help="Automatically apply updates without prompting")
    parser_update.add_argument("-a", "--all", action="store_true", help="Full workstation upgrade: git + Homebrew + Mise + test")
    parser_update.add_argument("-t", "--tools", action="store_true", help="Update Homebrew and Mise tools only")
    parser_update.add_argument("--test", action="store_true", help="Run deep integration tests after update")
    parser_update.add_argument("--no-prune", action="store_true", help="Keep links, caches and packages removed upstream")

    # dot link
    parser_link = subparsers.add_parser("link", help="Audit or auto-heal declarative symlinks")
    parser_link.add_argument("-f", "--fix", action="store_true", help="Automatically create or re-point symlinks")

    args = parser.parse_args()

    if not args.subcommand or args.subcommand == "status":
        sys.exit(run_status())
    elif args.subcommand == "doctor" or args.subcommand == "link":
        sys.exit(run_doctor(fix=args.fix))
    elif args.subcommand == "test":
        sys.exit(run_tests())
    elif args.subcommand == "bench":
        sys.exit(run_bench(iterations=args.iterations))
    elif args.subcommand == "clean":
        sys.exit(run_clean(dry_run=args.dry_run, clean_all=args.all))
    elif args.subcommand == "prune":
        sys.exit(run_prune(ref=args.ref, dry_run=args.dry_run, orphans=args.orphans))
    elif args.subcommand == "update":
        sys.exit(run_update(
            check_only=args.check,
            auto_apply=args.yes,
            update_all=args.all,
            tools_only=args.tools,
            test_after=args.test,
            prune=not args.no_prune,
        ))

if __name__ == "__main__":
    main()
