"""Run both complete chips through the same standalone Yosys/ABC mapping."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TOP = "tt_um_rayforge_3d"


def tool_path(path):
    if os.name == "nt":
        # Native ABC is invoked through a shell. A Windows short name keeps
        # spaces and shell characters out of its executable and temp paths.
        import ctypes
        buffer = ctypes.create_unicode_buffer(32768)
        length = ctypes.windll.kernel32.GetShortPathNameW(str(path), buffer, len(buffer))
        if 0 < length < len(buffer):
            return buffer.value
    return str(path)


def relative(path, work):
    return Path(os.path.relpath(path, work)).as_posix()


def map_design(yosys, source, library, work, label):
    files = " ".join(f'"{relative(p, work)}"' for p in sorted((source / "src").glob("*.v")))
    lib = f'"{relative(library, work)}"'
    script = work / f"{label}.ys"
    log = work / f"{label}.log"
    abc = ""
    if os.name == "nt" and (Path(yosys).parent / "yosys-abc.exe").is_file():
        abc = f" -exe {Path(tool_path(Path(yosys).with_name('yosys-abc.exe'))).as_posix()}"
    script.write_text(
        f"read_liberty -lib {lib}\n"
        f"read_verilog {files}\n"
        f"synth -top {TOP} -flatten -noabc\n"
        "delete t:$scopeinfo\n"
        f"dfflibmap -liberty {lib}\n"
        f"abc{abc} -D 39720 -liberty {lib}\n"
        "clean\n"
        "check -assert\n"
        f"stat -liberty {lib}\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    if os.name == "nt":
        scratch = tool_path(work)
        env.update(TEMP=scratch, TMP=scratch, TMPDIR=scratch)
    with log.open("wb") as stream:
        subprocess.run([tool_path(yosys), "-s", script.name], cwd=work, env=env,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    report = log.read_text(encoding="utf-8", errors="replace")
    areas = re.findall(r"Chip area for module .*?:\s*([0-9]+[.][0-9]+)", report)
    if len(areas) != 1 or "Area for cell type" in report:
        raise ValueError(f"Incomplete mapping area in {log}")
    return float(areas[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--unbiased", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    library = args.liberty.resolve()
    yosys = str(Path(args.yosys).resolve()) if Path(args.yosys).exists() else args.yosys
    version = subprocess.check_output([yosys, "-V"], text=True).strip()
    print(version, flush=True)
    print(f"Liberty SHA-256 {hashlib.sha256(library.read_bytes()).hexdigest()}", flush=True)
    areas = {
        "biased": map_design(yosys, ROOT, library, work, "biased"),
        "unbiased": map_design(yosys, args.unbiased.resolve(), library, work, "unbiased"),
    }
    for name, area in areas.items():
        print(f"{name}: {area:.4f} um^2")
    print(f"Unbiased minus biased: {areas['unbiased'] - areas['biased']:+.4f} um^2")


if __name__ == "__main__":
    main()
