# ----------------------------------------------------------------------------
# Project : NetScope
# Author  : AMiran Kimadze (itsarmen)
# GitHub  : https://github.com/itsarmen
# Email   : amoswaper@gmail.com
# Web     : https://xrow.asia
# ----------------------------------------------------------------------------

"""Build the Windows app and its installer (companion to run_windows.py).

Usage (from the repo root):
    python tools/build_windows.py              # release exe + signed-ready installer
    python tools/build_windows.py --sign       # + self-signed code signature
    python tools/build_windows.py --exe-only   # release exe only, no installer

Delegates to run_windows.py so there is exactly one build implementation.
"""

from __future__ import annotations

import sys

import run_windows


def main() -> int:
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(__doc__)
        print("All run_windows.py installer flags (--sign, --cert-password,")
        print("--no-pubget, ...) are passed through as well.")
        return 0
    argv = ["build_windows.py", "--installer"]
    if "--exe-only" in sys.argv[1:]:
        argv = ["build_windows.py", "--build-only", "--release"]
    else:
        argv += [a for a in sys.argv[1:] if a != "--exe-only"]
    sys.argv = argv
    return run_windows.main()


if __name__ == "__main__":
    sys.exit(main())
