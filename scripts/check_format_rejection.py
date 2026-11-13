"""Check native malformed-format diagnostics without assuming an output stream."""
from pathlib import Path
import subprocess

exe = Path("_build/native/debug/build/bobzhang/format_fuzz/format_fuzz.exe")
for fmt, message in [
    ("%{%d", 'invalid format "%{%d": unclosed sub-format, expected "%}" at character number 4'),
    ("%{%d%)", "invalid format \"%{%d%)\": at character number 5, character '}' expected, read ')'"),
]:
    script = "printf " + fmt.encode().hex() + "\n"
    result = subprocess.run([str(exe)], input=script, capture_output=True, text=True)
    assert result.returncode != 0, (fmt, result)
    diagnostic = result.stdout or result.stderr
    assert diagnostic.splitlines()[0] == message, (fmt, result)
print("Native malformed-format rejection: 2 cases passed")
