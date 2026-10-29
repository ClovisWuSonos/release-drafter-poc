"""Many-case test of chunk.sh: fixed edge cases, SHA-length sweep, big inputs, and a seeded differential fuzz
against a Python oracle. Runs chunk.sh under the same flags GitHub uses for `shell: bash`."""
import json, os, random, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
CHUNK = os.path.join(HERE, "chunk.sh")
BASH = [shutil.which("bash"), "--noprofile", "--norc", "-e", "-o", "pipefail"]
BASE = "https://github.com/example-org/example-repo/compare"
WARN = "::warning::No Compare changes link added: jq command failed"
HEX = re.compile(r"[0-9a-fA-F]{7,40}")

def run(prev, new="bbbbbbb", path=None):
    with tempfile.NamedTemporaryFile("r+") as lf:
        p = subprocess.run(BASH + [CHUNK], env={"PATH": path or os.environ["PATH"], "LINKS_FILE": lf.name,
                           "INPUT_PREVIOUS_REGION_INFO": prev, "INPUT_COMMIT_SHA": new}, capture_output=True, text=True)
        links = [l for l in lf.read().split("\n") if l != ""]
    return p.returncode, links, p.stdout, p.stderr

def oracle(prev_obj, new):
    """(expected_links, expect_failure) for valid JSON. Mirrors the chunk: invalid/equal SHAs skipped,
    non-string sha (number/true/array/object) makes jq fail, output split on newlines, empty lines dropped."""
    if not HEX.fullmatch(new): return [], False, "guard"
    regs = []
    for k, v in prev_obj.items():
        sha = v.get("sha") if isinstance(v, dict) else None
        if sha is not None and sha is not False and not isinstance(sha, str): return [], True, "jq-error"
        s = sha if isinstance(sha, str) else ""
        if HEX.fullmatch(s) and s.lower() != new.lower(): regs.append((k, s))
    if not regs: return [], False, "none"
    if len({s for _, s in regs}) == 1: out = f"[Compare changes]({BASE}/{regs[0][1]}..{new})"
    else: out = "\n".join(f"[Compare ({k})]({BASE}/{s}..{new})" for k, s in regs)
    return [l for l in out.split("\n") if l != ""], False, "links"

stats, fails, notes = {}, [], []
def check(group, name, ok, detail=""):
    s = stats.setdefault(group, [0, 0]); s[0] += 1
    if not ok: s[1] += 1; fails.append((group, name, detail))

# ---- A. invalid / non-object JSON: must fail soft (exit 0, no link, warning on stdout, something on stderr)
BAD = ["not json", "{", "}", "{\"a\":", "[1,", "{'a':1}", "{\"a\":1,}", "undefined", "{\"a\":{\"sha\":\"aaaaaaa\"}", "\"unterminated",
       "{\"a\" 1}", "<xml/>", "{{}}", "[[", "tru",  "null", "5", "-1", "true", "false", "\"abc\"", "\"\"",
       "{\"a\":{\"sha\":1234567}}", "{\"a\":{\"sha\":true}}", "{\"a\":{\"sha\":[\"aaaaaaa\"]}}", "{\"a\":{\"sha\":{\"x\":1}}}",
       "{\"a\":{\"sha\":\"aaaaaaa\"},\"b\":{\"sha\":42}}"]
for t in BAD:
    rc, links, so, se = run(t)
    check("A invalid/odd input fails soft", repr(t), rc == 0 and not links and so.strip() == WARN and se.strip() != "", (rc, links, so, se[:80]))

# ---- B. inputs that must be silent (no link, no warning)
for name, prev in [("empty", ""), ("whitespace only", "   "), ("newline only", "\n"), ("{}", "{}"), ("[]", "[]"),
                   ("region value null", '{"a":null}'), ("region value string", '{"a":"aaaaaaa"}'), ("region value number", '{"a":5}'),
                   ("region value array", '{"a":["aaaaaaa"]}'), ("sha null", '{"a":{"sha":null}}'), ("sha false", '{"a":{"sha":false}}'),
                   ("sha missing", '{"a":{"version":"1"}}'), ("sha empty", '{"a":{"sha":""}}'), ("sha too short", '{"a":{"sha":"abc123"}}'),
                   ("sha too long", '{"a":{"sha":"' + "a" * 41 + '"}}'), ("sha non-hex", '{"a":{"sha":"gggggggg"}}'),
                   ("sha with space", '{"a":{"sha":"aaaaaaa "}}'), ("sha with newline", '{"a":{"sha":"aaaaaaa\\n"}}'),
                   ("sha with CR", '{"a":{"sha":"aaaaaaa\\r"}}'), ("sha with tab", '{"a":{"sha":"\\taaaaaaa"}}'), ("sha unicode", '{"a":{"sha":"aaaaaaaé"}}'),
                   ("same as new", '{"a":{"sha":"bbbbbbb"}}'), ("same as new, other case", '{"a":{"sha":"BBBBBBB"}}')]:
    rc, links, so, se = run(prev)
    check("B silent / no link", name, rc == 0 and not links and so == "", (rc, links, so, se[:80]))

# ---- C. new commit SHA sweep: every length 7..40 valid, boundaries and bad forms rejected without calling jq
prev = '{"a":{"sha":"1111111"}}'
for n in range(7, 41):
    new = "f" * n; rc, links, so, se = run(prev, new)
    check("C new SHA valid lengths 7..40", f"len {n}", rc == 0 and links == [f"[Compare changes]({BASE}/1111111..{new})"] and so == "", (links, so))
for name, new in [("len 6", "f" * 6), ("len 41", "f" * 41), ("empty", ""), ("space", " "), ("trailing space", "bbbbbbb "), ("leading space", " bbbbbbb"),
                  ("trailing newline", "bbbbbbb\n"), ("non-hex", "zzzzzzz"), ("paren", "bbbbbbb)"), ("semicolon", "bbbbbbb;x"), ("unicode", "bbbbbbbé"), ("0x prefix", "0xbbbbbbb")]:
    rc, links, so, se = run(prev, new)
    check("C new SHA invalid -> silent no link", name, rc == 0 and not links and so == "" and se == "", (rc, links, so, se[:60]))
rc, links, so, se = run(prev, "ABCDEF1"); check("C new SHA upper-case accepted", "upper", links == [f"[Compare changes]({BASE}/1111111..ABCDEF1)"], links)

# ---- D. link logic, handcrafted
def want(prev_obj, new="bbbbbbb"): return oracle(prev_obj, new)[0]
cases = {
 "one region": {"us-east-1": {"sha": "aaaaaaa"}},
 "two regions same sha -> one link": {"a": {"sha": "aaaaaaa"}, "b": {"sha": "aaaaaaa"}},
 "two regions differ -> two links": {"a": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}},
 "three regions, two share": {"a": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}, "c": {"sha": "ccccccc"}},
 "one region already at new sha": {"a": {"sha": "aaaaaaa"}, "b": {"sha": "bbbbbbb"}},
 "all regions at new sha": {"a": {"sha": "bbbbbbb"}, "b": {"sha": "BBBBBBB"}},
 "same commit, different case -> distinct (two links)": {"a": {"sha": "aaaaaaa"}, "b": {"sha": "AAAAAAA"}},
 "short and full sha of one commit -> two links": {"a": {"sha": "abcdef1"}, "b": {"sha": "abcdef1" + "0" * 33}},
 "40-char sha": {"a": {"sha": "a" * 40}},
 "extra fields ignored": {"a": {"sha": "aaaaaaa", "version": "1.2.3", "extra": [1, 2]}},
 "bad region among good": {"a": {"sha": "zz"}, "b": {"sha": "ccccccc"}},
 "null region among good": {"a": None, "b": {"sha": "ccccccc"}},
 "key with space": {"us east": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}},
 "key with brackets": {"a](x)[": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}},
 "key empty": {"": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}},
 "key unicode": {"région-é": {"sha": "aaaaaaa"}, "b": {"sha": "ccccccc"}},
 "key with newline (output split on lines)": {"a\nb": {"sha": "aaaaaaa"}, "c": {"sha": "ccccccc"}},
 "key with tab": {"a\tb": {"sha": "aaaaaaa"}, "c": {"sha": "ccccccc"}},
 "key with backslash/quote": {"a\\b\"c": {"sha": "aaaaaaa"}, "d": {"sha": "ccccccc"}},
 "region order preserved": {"z": {"sha": "aaaaaaa"}, "a": {"sha": "ccccccc"}, "m": {"sha": "ddddddd"}},
}
for name, obj in cases.items():
    rc, links, so, se = run(json.dumps(obj, ensure_ascii=False))
    check("D handcrafted link logic", name, rc == 0 and links == want(obj) and so == "", (rc, links, want(obj), so))

# ---- E. size
big = {f"region-{i}": {"sha": ("%07x" % (i % 7 + 1))} for i in range(500)}
rc, links, so, se = run(json.dumps(big)); check("E size", "500 regions, 7 distinct shas", rc == 0 and links == want(big), (rc, len(links)))
same = {f"region-{i}": {"sha": "aaaaaaa"} for i in range(2000)}
rc, links, so, se = run(json.dumps(same)); check("E size", "2000 regions same sha -> 1 link", rc == 0 and links == want(same), (rc, len(links)))
pad = {"a": {"sha": "aaaaaaa", "blob": "x" * 100000}}
rc, links, so, se = run(json.dumps(pad)); check("E size", "100 KB extra field (Linux caps one env var at 128 KB)", rc == 0 and links == want(pad), (rc, len(links)))
deep = '{"a":{"sha":"aaaaaaa","n":' + "[" * 300 + "]" * 300 + "}}"
rc, links, so, se = run(deep); check("E size", "deeply nested extra field", rc == 0 and links == [f"[Compare changes]({BASE}/aaaaaaa..bbbbbbb)"], (rc, links, so, se[:60]))

# ---- F. jq not installed
nojq = tempfile.mkdtemp()
rc, links, so, se = run('{"a":{"sha":"aaaaaaa"}}', path=nojq); shutil.rmtree(nojq)
check("F jq missing", "exit 0, no link, warning", rc == 0 and not links and so.strip() == WARN and se.strip() != "", (rc, links, so, se[:60]))

# ---- G. seeded differential fuzz against the oracle (valid JSON only)
random.seed(20261029)
SH = ["aaaaaaa", "ccccccc", "ddddddd1", "e" * 40, "f" * 12, "bbbbbbb", "BBBBBBB", "AAAAAAA", "abcdef1", "0123456789abcdef"]
BADSH = ["", "zz", "abc", "g" * 8, "a" * 41, "aaaaaaa ", " aaaaaaa", "aaaaaaa\n", "aaaa-aaa", "ééééééé"]
KEYS = ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-2", "a b", "x](y)", "", "é", "k\nl", "q\"r"]
NEWS = ["bbbbbbb", "b" * 40, "BBBBBBB", "aaaaaaa", "abcdef1", "1234567", "zz", "", "bbbbbbb)"]
for i in range(3000):
    obj = {}
    for k in random.sample(KEYS, random.randint(0, 6)):
        r = random.random()
        if r < 0.60: v = {"sha": random.choice(SH), "version": "1"}
        elif r < 0.72: v = {"sha": random.choice(BADSH)}
        elif r < 0.78: v = {"sha": None}
        elif r < 0.83: v = {"version": "1"}
        elif r < 0.87: v = None
        elif r < 0.91: v = "aaaaaaa"
        elif r < 0.94: v = {"sha": random.choice([1234567, True, ["aaaaaaa"], {"x": 1}])}
        else: v = {"sha": False}
        obj[k] = v
    new = random.choice(NEWS); text = json.dumps(obj, ensure_ascii=bool(i % 2))
    exp, expfail, why = oracle(obj, new)
    rc, links, so, se = run(text, new)
    if expfail: ok = rc == 0 and not links and so.strip() == WARN and se.strip() != ""
    else: ok = rc == 0 and links == exp and so == ""
    check("G fuzz vs oracle (3000)", f"#{i} new={new!r} {text[:90]}", ok, (rc, links, exp, so[:50]))

# ---- H. observations (informational, not failures)
rc, links, so, se = run('{"a":{"sha":"aaaaaaa"}} not json')
notes.append(f"first doc valid + trailing garbage: rc={rc} links={len(links)} warning={'yes' if WARN in so else 'no'}  (partial jq output is still used when jq fails midway)")
rc, links, so, se = run('{"a":{"sha":"aaaaaaa"}} {"b":{"sha":"ccccccc"}}')
notes.append(f"two JSON documents in one value: rc={rc} links={len(links)} warning={'yes' if WARN in so else 'no'}")
rc, links, so, se = run('[{"sha":"aaaaaaa"}]')
notes.append(f"JSON array root: rc={rc} links={links}")

total = sum(s[0] for s in stats.values()); bad = sum(s[1] for s in stats.values())
print(f"{'group':44} {'cases':>6} {'failed':>7}")
for g, (n, f) in stats.items(): print(f"{g:44} {n:>6} {f:>7}")
print(f"{'TOTAL':44} {total:>6} {bad:>7}")
for n in notes: print("NOTE:", n)
for g, name, d in fails[:15]: print(f"FAIL [{g}] {name}\n      {d}")
sys.exit(1 if bad else 0)
