import json
import subprocess
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SANITIZER = ROOT / "rightpanel" / "components" / "NotificationBodySanitizer.js"


def run_sanitizer(body):
    source = SANITIZER.read_text()
    script = textwrap.dedent(
        f"""
        const vm = require("vm");
        const source = {json.dumps(source)}
            .split("\\n")
            .filter(line => !line.trim().startsWith(".pragma"))
            .join("\\n");
        const context = {{}};
        vm.createContext(context);
        vm.runInContext(source, context);
        process.stdout.write(context.normalizeBodyForStyledText({json.dumps(body)}));
        """
    )
    return subprocess.check_output(["node", "-e", script], text=True)


def test_plain_text_is_escaped_before_newlines_become_br():
    assert run_sanitizer('2 < 3 && "quoted"\nnext') == "2 &lt; 3 &amp;&amp; &quot;quoted&quot;<br>next"


def test_whatsapp_header_link_is_stripped_before_escaping():
    body = '<a href="https://web.whatsapp.com/">WhatsApp</a>\nAlice <bob@example.com>'
    assert run_sanitizer(body) == "Alice &lt;bob@example.com&gt;"
