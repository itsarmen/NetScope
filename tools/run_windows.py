# ----------------------------------------------------------------------------
# Project : NetScope
# Author  : AMiran Kimadze (itsarmen)
# GitHub  : https://github.com/itsarmen
# Email   : amoswaper@gmail.com
# Web     : https://xrow.asia
# ----------------------------------------------------------------------------

"""Easily run the NetScope desktop app.

Usage (from the repo root):
    python tools/run_windows.py                  # flutter run -d windows (debug)
    python tools/run_windows.py --release        # flutter run --release -d windows
    python tools/run_windows.py --exe            # launch prebuilt exe, no rebuild
    python tools/run_windows.py --build-only     # flutter build windows, don't launch
    python tools/run_windows.py --analyze        # flutter analyze before running
    python tools/run_windows.py --installer      # release build + Inno Setup installer
    python tools/run_windows.py --installer --sign  # + self-signed code signature

Needs Flutter SDK with Windows desktop enabled:
    flutter config --enable-windows-desktop
For --installer: Inno Setup 6 (ISCC.exe), e.g.
    winget install -e --id JRSoftware.InnoSetup
For --sign: Windows SDK signtool (comes with Visual Studio / Windows SDK).
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
# Script lives in tools/; fall back to the script dir for exotic layouts.
ROOT = _HERE if (_HERE / "flutter-desktop-app").is_dir() else _HERE.parent
APP_DIR = ROOT / "flutter-desktop-app"

INSTALLER_DIR = ROOT / "installer"
ISS = INSTALLER_DIR / "netscope.iss"
CERT_DIR = INSTALLER_DIR / "cert"
PFX = CERT_DIR / "dev-sign.pfx"
CERT_SUBJECT = "CN=AMiran Kimadze (itsarmen)"
TIMESTAMP_URL = "http://timestamp.digicert.com"

# Candidates in order: PATH, then well-known Windows install spots.
FLUTTER_CANDIDATES = [
    "flutter.bat",
    "flutter",
    r"C:\flutter\bin\flutter.bat",
    r"E:\flutter\bin\flutter.bat",
    r"C:\src\flutter\bin\flutter.bat",
]

ISCC_CANDIDATES = [
    "ISCC.exe",
    "iscc",
    r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    r"C:\Program Files\Inno Setup 6\ISCC.exe",
    r"C:\Users\amirandev\AppData\Local\Programs\Inno Setup 6\ISCC.exe",
]


def find_flutter() -> str:
    for cand in FLUTTER_CANDIDATES:
        found = shutil.which(cand) or (cand if Path(cand).is_file() else None)
        if found:
            return found
    raise SystemExit(
        "ERROR: flutter not found.\n"
        "Install Flutter SDK and either add it to PATH or edit "
        "FLUTTER_CANDIDATES in run.py.\n"
        "See https://docs.flutter.dev/get-started/install/windows"
    )


def run(cmd: list[str], cwd: Path) -> int:
    print(f"$ {' '.join(cmd)}  (cwd={cwd})", flush=True)
    try:
        return subprocess.call(cmd, cwd=str(cwd))
    except KeyboardInterrupt:
        print("\nInterrupted.", flush=True)
        return 130


def find_built_exe(release: bool) -> Path | None:
    build_root = APP_DIR / "build" / "windows" / "x64" / "runner"
    ordered = ["Release", "Debug"] if release else ["Debug", "Release"]
    for cfg in ordered:
        exe = build_root / cfg / "netscope.exe"
        if exe.is_file():
            return exe
    return None


def find_iscc() -> str:
    for cand in ISCC_CANDIDATES:
        found = shutil.which(cand) or (cand if Path(cand).is_file() else None)
        if found:
            return found
    raise SystemExit(
        "ERROR: Inno Setup compiler (ISCC.exe) not found.\n"
        "Install Inno Setup 6: https://jrsoftware.org/isdl.php\n"
        "or: winget install -e --id JRSoftware.InnoSetup"
    )


def find_signtool() -> str:
    found = shutil.which("signtool.exe")
    if found:
        return found
    kits = Path(r"C:\Program Files (x86)\Windows Kits\10\bin")
    if kits.is_dir():
        matches = sorted(kits.glob("*/x64/signtool.exe"), reverse=True)
        if matches:
            return str(matches[0])
    raise SystemExit(
        "ERROR: signtool.exe not found.\n"
        "Install Visual Studio (Desktop C++ workload) or the Windows SDK:\n"
        "https://developer.microsoft.com/windows/downloads/windows-sdk/"
    )


def ensure_dev_cert(password: str) -> Path:
    """Create (once) a self-signed dev code-signing cert, trust it locally,
    and export installer/cert/dev-sign.pfx. Returns the PFX path."""
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    if PFX.is_file():
        print(f"Reusing dev cert: {PFX}", flush=True)
        return PFX
    # NOTE: trust is installed via certutil, not the .NET X509Store API —
    # the API can pop a confirmation dialog and hang headless sessions.
    ps = (
        "$ErrorActionPreference='Stop';"
        f"$subject='{CERT_SUBJECT}';"
        f"$pw=ConvertTo-SecureString '{password}' -AsPlainText -Force;"
        "$cert=Get-ChildItem Cert:\\CurrentUser\\My -CodeSigningCert "
        "| Where-Object {$_.Subject -eq $subject} | Select-Object -First 1;"
        "if (-not $cert) {"
        "  $cert=New-SelfSignedCertificate -Type CodeSigningCert "
        "-Subject $subject -CertStoreLocation Cert:\\CurrentUser\\My "
        "-KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(5);"
        "}"
        f"Export-PfxCertificate -Cert $cert -FilePath '{PFX}' "
        "-Password $pw -Force | Out-Null;"
        "'CERT:' + $cert.Thumbprint"
    )
    r = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise SystemExit(f"ERROR: could not create dev cert:\n{r.stderr}")
    cer = CERT_DIR / "dev-sign.cer"
    export_ps = (
        "Add-Type -AssemblyName System.Security;"
        "$col=New-Object Security.Cryptography.X509Certificates."
        "X509Certificate2Collection;"
        f"$col.Import('{PFX}','{password}','Exportable');"
        f"[IO.File]::WriteAllBytes('{cer}',$col[0].Export('Cert'))"
    )
    r2 = subprocess.run(["powershell", "-NoProfile", "-Command", export_ps],
                        capture_output=True, text=True, timeout=60)
    if r2.returncode != 0:
        raise SystemExit(f"ERROR: could not export .cer:\n{r2.stderr}")
    for store in ("Root", "TrustedPublisher"):
        rc = subprocess.call(["certutil", "-user", "-addstore",
                              store, str(cer)])
        if rc != 0:
            raise SystemExit(f"ERROR: certutil trust failed ({store}).")
    print(f"Dev cert ready ({r.stdout.strip()}), trusted for this user.",
          flush=True)
    return PFX


def sign_file(signtool: str, pfx: Path, password: str, target: Path) -> None:
    cmd = [signtool, "sign", "/fd", "SHA256", "/tr", TIMESTAMP_URL,
           "/td", "SHA256", "/f", str(pfx), "/p", password, str(target)]
    print(f"$ {' '.join(cmd)}", flush=True)
    if subprocess.call(cmd) != 0:
        raise SystemExit(f"ERROR: signing failed: {target}")


def _md_to_txt(md: str) -> str:
    """Minimal Markdown → plain text for the Inno wizard pages."""
    out = []
    for line in md.splitlines():
        line = re.sub(r"^#{1,6}\s*", "", line)
        line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", line)
        line = line.replace("**", "").replace("__", "")
        out.append(line.rstrip())
    return "\n".join(out).strip() + "\n"


def _installer_texts() -> tuple[str, str]:
    """Render LICENSE + AGREEMENT.md to Temp .txt files (no drift)."""
    tmp = Path.home() / "AppData" / "Local" / "Temp" / "opencode"
    tmp.mkdir(parents=True, exist_ok=True)
    license_txt = tmp / "installer-license.txt"
    agreement_txt = tmp / "installer-agreement.txt"
    license_txt.write_text(
        (ROOT / "LICENSE").read_text(encoding="utf-8"), encoding="utf-8")
    agreement_txt.write_text(
        _md_to_txt((ROOT / "AGREEMENT.md").read_text(encoding="utf-8")),
        encoding="utf-8")
    return str(license_txt), str(agreement_txt)


def build_installer(flutter: str, sign: bool, cert_password: str) -> int:
    if not ISS.is_file():
        raise SystemExit(f"ERROR: installer script not found: {ISS}")
    if run([flutter, "build", "windows", "--release"], APP_DIR) != 0:
        return 1
    exe = find_built_exe(True)
    if exe is None:
        raise SystemExit("ERROR: release build produced no exe.")
    iscc = find_iscc()
    license_txt, agreement_txt = _installer_texts()
    cmd = [iscc, str(ISS),
           f"/DLicenseTxt={license_txt}",
           f"/DAgreementTxt={agreement_txt}"]
    if sign:
        signtool = find_signtool()
        pfx = ensure_dev_cert(cert_password)
        sign_file(signtool, pfx, cert_password, exe)
        # ISCC's /S value is quote-parsed by Inno itself, so the helper
        # binary must live in a space-free path (no nested quoting hell).
        helper = (Path.home() / "AppData" / "Local" / "Temp" / "opencode"
                  / "signtool.exe")
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(signtool, helper)
        # No manual quotes: Python wraps this argv element in "..." itself
        # (the helper path is space-free, so no nested quoting is needed).
        cmd += [
            "/DSignEnabled=1",
            f"/Sdevsign={helper} sign /fd SHA256 /tr {TIMESTAMP_URL} "
            f"/td SHA256 /f {pfx} /p {cert_password} $f",
        ]
    code = run(cmd, INSTALLER_DIR)
    if code == 0:
        setups = sorted((INSTALLER_DIR / "output").glob("*.exe"))
        print(f"Installer ready: {setups[-1] if setups else '(see output/)'}",
              flush=True)
        if sign:
            print("Signed with the local dev cert (trusted on THIS machine "
                  "only). Other PCs still show SmartScreen until you ship "
                  "with a real OV/EV code-signing certificate.",
                  flush=True)
    return code


def main() -> int:
    ap = argparse.ArgumentParser(description="Run the NetScope desktop app.")
    ap.add_argument("--release", action="store_true",
                    help="use release instead of debug build")
    ap.add_argument("--exe", action="store_true",
                    help="launch the prebuilt exe instead of `flutter run`")
    ap.add_argument("--build-only", action="store_true",
                    help="only `flutter build windows`, do not launch")
    ap.add_argument("--analyze", action="store_true",
                    help="run `flutter analyze` first, stop on failure")
    ap.add_argument("--pubget", dest="pubget", action="store_true", default=True,
                    help="run `flutter pub get` first (default: on)")
    ap.add_argument("--no-pubget", dest="pubget", action="store_false",
                    help="skip `flutter pub get`")
    ap.add_argument("--device", default="windows",
                    help="flutter device id (default: windows)")
    ap.add_argument("--installer", action="store_true",
                    help="release build + compile Inno Setup installer")
    ap.add_argument("--sign", action="store_true",
                    help="with --installer: self-signed code signature")
    ap.add_argument("--cert-password", default="netscope-dev",
                    help="password for the dev-sign PFX (default: dev value)")
    args = ap.parse_args()

    if args.sign and not args.installer:
        raise SystemExit("ERROR: --sign needs --installer.")

    if not (APP_DIR / "pubspec.yaml").is_file():
        raise SystemExit(f"ERROR: app dir not found: {APP_DIR}")

    flutter = find_flutter()
    cfg = "Release" if args.release else "Debug"

    if args.exe:
        exe = find_built_exe(args.release)
        if exe is None:
            raise SystemExit(
                f"ERROR: no prebuilt exe found under "
                f"build/windows/x64/runner/{{Debug,Release}}/.\n"
                f"Run `python run.py` or `python run.py --build-only` first."
            )
        print(f"Launching {exe}", flush=True)
        subprocess.Popen([str(exe)], cwd=str(exe.parent))
        return 0

    if args.pubget:
        if run([flutter, "pub", "get"], APP_DIR) != 0:
            return 1

    if args.analyze:
        if run([flutter, "analyze"], APP_DIR) != 0:
            print("`flutter analyze` failed, aborting.", flush=True)
            return 1

    if args.build_only:
        code = run([flutter, "build", "windows",
                    "--release" if args.release else "--debug"], APP_DIR)
        if code == 0:
            exe = find_built_exe(args.release)
            print(f"Built {cfg}: {exe}", flush=True)
        return code

    if args.installer:
        return build_installer(flutter, args.sign, args.cert_password)

    # Normal path: dev run with hot-reload (press `r` / `R` / `q` in terminal).
    return run([flutter, "run", "-d", args.device,
                "--release" if args.release else "--debug"], APP_DIR)


if __name__ == "__main__":
    sys.exit(main())
