from __future__ import annotations

import argparse
import glob
import shutil
import re
import sys
import subprocess
import os
import shutil
import tempfile
from pathlib import Path

try:
    from pylatex import Document, Package
    from pylatex.errors import CompilerError
    from pylatex.utils import NoEscape
except ImportError:
    Document = None
    Package = None
    NoEscape = None
    CompilerError = RuntimeError


def extract_braced(source: str, command: str) -> str | None:
    match = re.search(rf"\\{re.escape(command)}\s*\{{", source)
    if not match:
        return None

    depth = 0
    start = match.end() - 1
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return rf"\{command}{{" + source[start + 1:index] + "}"
    return None


def package_names(preamble: str) -> list[str]:
    names: list[str] = []
    for match in re.findall(r"\\usepackage(?:\[[^\]]*\])?\{([^}]+)\}", preamble):
        names.extend(name.strip() for name in match.split(",") if name.strip())
    return list(dict.fromkeys(names))


def resolve_compiler(compiler: str) -> str:
    compiler_path = Path(compiler).expanduser()
    if compiler_path.is_file():
        return str(compiler_path.resolve())

    discovered = shutil.which(compiler)
    if discovered:
        return discovered

    candidates: list[str] = []
    local_app_data = os.environ.get("LOCALAPPDATA")
    program_files = os.environ.get("PROGRAMFILES")
    program_files_x86 = os.environ.get("PROGRAMFILES(X86)")

    if local_app_data:
        candidates.extend([
            str(Path(local_app_data) / "Programs" / "MiKTeX" / "miktex" / "bin" / "x64" / f"{compiler}.exe"),
            str(Path(local_app_data) / "Programs" / "MiKTeX" / "miktex" / "bin" / f"{compiler}.exe"),
            str(Path(local_app_data) / "MiKTeX" / "miktex" / "bin" / "x64" / f"{compiler}.exe"),
            str(Path(local_app_data) / "MiKTeX" / "miktex" / "bin" / f"{compiler}.exe"),
        ])
    for directory in (program_files, program_files_x86):
        if directory:
            candidates.append(str(Path(directory) / "MiKTeX" / "miktex" / "bin" / "x64" / f"{compiler}.exe"))
            candidates.append(str(Path(directory) / "MiKTeX" / "miktex" / "bin" / f"{compiler}.exe"))

    candidates.extend(glob.glob(r"C:\texlive\*\bin\windows\\" + f"{compiler}.exe"))
    candidates.extend(glob.glob(r"C:\texlive\*\bin\*\\" + f"{compiler}.exe"))

    for candidate in candidates:
        if Path(candidate).is_file():
            return str(Path(candidate).resolve())

    raise RuntimeError(
        f"LaTeX compiler '{compiler}' was not found. "
        "Install MiKTeX or TeX Live, or pass its executable with --compiler."
    )


def compile_latex(source: Path, output_dir: Path, compiler: str, keep_tex: bool) -> Path:
    if Document is None:
        raise RuntimeError("PyLaTeX is not installed. Run: python -m pip install -r research/requirements.txt")

    source = source.resolve()
    if not source.is_file():
        raise FileNotFoundError(f"LaTeX source not found: {source}")

    text = source.read_text(encoding="utf-8")
    begin = text.find(r"\begin{document}")
    end = text.find(r"\end{document}", begin)
    if begin < 0 or end < 0:
        raise ValueError(f"Could not find document environment in: {source}")

    preamble = text[:begin]
    body = text[begin + len(r"\begin{document}"):end].strip()

    document = Document(
        str(output_dir.resolve() / source.stem),
        documentclass="IEEEtran",
        document_options="conference",
    )
    for name in package_names(preamble):
        document.packages.append(Package(name))

    for command in ("title", "author"):
        value = extract_braced(preamble, command)
        if value:
            document.append(NoEscape(value))
    document.append(NoEscape(body))

    output_dir.mkdir(parents=True, exist_ok=True)
    compiler = resolve_compiler(compiler)
    build_dir = tempfile.TemporaryDirectory(prefix="mlrc-latex-", dir=str(output_dir.resolve()))
    try:
        build_base = Path(build_dir.name) / source.stem
        document.generate_pdf(
            str(build_base),
            compiler=compiler,
            compiler_args=["-interaction=nonstopmode"],
            clean=not keep_tex,
            clean_tex=not keep_tex,
        )
        generated_pdf = build_base.with_suffix(".pdf")
        final_pdf = output_dir.resolve() / f"{source.stem}.pdf"
        shutil.copy2(generated_pdf, final_pdf)
        if keep_tex:
            shutil.copy2(build_base.with_suffix(".tex"), output_dir.resolve() / f"{source.stem}.tex")
    finally:
        build_dir.cleanup()
    return final_pdf


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile a LaTeX document with PyLaTeX.")
    parser.add_argument(
        "source",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parent / "IEEE_DRAFT.tex",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent,
    )
    parser.add_argument(
        "--compiler",
        default="pdflatex",
        help="LaTeX compiler name or executable path (default: pdflatex)",
    )
    parser.add_argument("--keep-tex", action="store_true", help="Keep generated .tex and build files")
    args = parser.parse_args()

    try:
        pdf = compile_latex(args.source, args.output_dir, args.compiler, args.keep_tex)
    except (FileNotFoundError, RuntimeError, ValueError, CompilerError, subprocess.CalledProcessError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    print(pdf)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
