# flake/checks/docs-includes.py
# Resolve every mdbook include and relative link under a book source directory
"""Fail when a documentation page points at something that is not there.

mdbook logs a missing include and renders the page with a gap where the text
belonged, and it exits 0 either way. This script reads the same directives
mdbook reads and exits 1 on the first run that finds any of these:

- an include, rustdoc_include or playground directive naming a missing file
- an include naming an anchor whose opening or closing marker is absent from
  the target, or a line range that starts past the end of the target
- a relative link to a file that does not exist
- a link fragment that matches no heading id in the page it points at

Paths resolve relative to the file that holds the directive, which is how
mdbook resolves them, and included text is searched for further directives.

Usage: docs-includes.py SRC [--generated PATH]...

PATH is relative to SRC and names a page a build step writes later. A link to
it is accepted while the file is absent and its fragments are not checked.
"""

import argparse
import re
import sys
from pathlib import Path

DIRECTIVE = re.compile(r"(\\)?\{\{\s*#([a-zA-Z0-9_]+)\s+([^}]+?)\s*\}\}")
FILE_DIRECTIVES = {"include", "rustdoc_include", "playground"}
RANGE_DIRECTIVES = {"include", "rustdoc_include"}
MAX_DEPTH = 10

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")
HEADING_ID = re.compile(r"\s*\{([^}]*)\}\s*$")
HTML_ID = re.compile(r"""<[a-zA-Z][^>]*\s(?:id|name)\s*=\s*["']([^"']+)["']""")
INLINE_CODE = re.compile(r"`[^`\n]*`")
INLINE_LINK = re.compile(r"\]\(\s*<?([^)\s>]*)>?(?:\s+\"[^\"]*\")?\s*\)")
REFERENCE_LINK = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def anchor_marker(kind, name):
    return re.compile(kind + r":\s*" + re.escape(name) + r"(?![\w-])")


class Checker:
    def __init__(self, src, generated):
        self.src = src.resolve()
        self.generated = {(self.src / g).resolve() for g in generated}
        self.errors = []
        self.expanded = {}
        self.ids = {}

    def label(self, path):
        try:
            return str(path.relative_to(self.src.parent.parent))
        except ValueError:
            return str(path)

    def error(self, page, line, what, reason):
        self.errors.append(f"{self.label(page)}:{line}: {what}: {reason}")

    def select(self, target, spec, fail):
        """Return the lines of target that spec names, or None after fail()."""
        lines = target.read_text(encoding="utf-8").splitlines()
        if not spec or spec == [""]:
            return lines
        first = spec[0]
        if first.isdigit() or (first == "" and len(spec) > 1):
            start = int(first) if first else 1
            last = spec[1] if len(spec) > 1 else first
            end = int(last) if last.isdigit() else len(lines)
            if start < 1 or start > len(lines):
                fail(f"line {start} is past the end, the file has {len(lines)} lines")
                return None
            if end < start:
                fail(f"the range ends at line {end}, before it starts")
                return None
            return lines[start - 1 : end]
        opening = anchor_marker("ANCHOR", first)
        closing = anchor_marker("ANCHOR_END", first)
        begin = next((i for i, l in enumerate(lines) if opening.search(l)), None)
        if begin is None:
            fail(f"no ANCHOR marker named '{first}' in the target")
            return None
        finish = next(
            (i for i in range(begin + 1, len(lines)) if closing.search(lines[i])), None
        )
        if finish is None:
            fail(f"no ANCHOR_END marker named '{first}' after its ANCHOR")
            return None
        return [
            l
            for l in lines[begin + 1 : finish]
            if "ANCHOR:" not in l and "ANCHOR_END:" not in l
        ]

    def expand(self, text, holder, page, page_line, depth):
        """Replace each directive in text with the lines it selects."""

        def substitute(match, line):
            escaped, kind, args = match.group(1), match.group(2), match.group(3)
            if escaped or kind not in FILE_DIRECTIVES:
                return match.group(0)
            what = match.group(0)
            if holder != page:
                what += f" (reached through {self.label(holder)})"

            def fail(reason):
                self.error(page, line, what, reason)

            parts = args.split(":")
            if kind == "playground":
                parts = [args.split()[0]]
            target = (holder.parent / parts[0]).resolve()
            if not target.is_file():
                fail(f"no file at {self.label(target)}")
                return ""
            if depth >= MAX_DEPTH:
                fail(f"includes nest deeper than {MAX_DEPTH} levels")
                return ""
            spec = parts[1:] if kind in RANGE_DIRECTIVES else []
            selected = self.select(target, spec, fail)
            if selected is None:
                return ""
            return self.expand("\n".join(selected), target, page, line, depth + 1)

        out = []
        for offset, row in enumerate(text.split("\n")):
            line = page_line or offset + 1
            out.append(DIRECTIVE.sub(lambda m, n=line: substitute(m, n), row))
        return "\n".join(out)

    def page_text(self, page):
        if page not in self.expanded:
            raw = page.read_text(encoding="utf-8")
            self.expanded[page] = self.expand(raw, page, page, None, 0)
        return self.expanded[page]

    @staticmethod
    def prose(text):
        """Yield (line number, text) for each line outside a fenced block."""
        fence = None
        for number, row in enumerate(text.split("\n"), 1):
            match = FENCE.match(row)
            if match:
                mark = match.group(1)
                if fence is None:
                    fence = mark
                elif mark[0] == fence[0] and len(mark) >= len(fence):
                    fence = None
                continue
            if fence is None:
                yield number, row

    def heading_ids(self, page):
        """The ids mdbook gives the headings of a page, plus explicit HTML ids."""
        if page in self.ids:
            return self.ids[page]
        ids = set()
        seen = {}
        for _, row in self.prose(self.page_text(page)):
            ids.update(HTML_ID.findall(row))
            match = HEADING.match(row)
            if not match:
                continue
            title = match.group(1)
            explicit = None
            attrs = HEADING_ID.search(title)
            if attrs:
                title = title[: attrs.start()]
                explicit = next(
                    (a[1:] for a in attrs.group(1).split() if a.startswith("#")), None
                )
            title = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", title)
            title = re.sub(r"<[^>]+>", "", title)
            slug = explicit or "".join(
                c.lower() if c.isalnum() or c in "_-" else "-"
                for c in title
                if c.isalnum() or c in "_-" or c.isspace()
            )
            count = seen.get(slug, 0)
            seen[slug] = count + 1
            ids.add(slug if count == 0 else f"{slug}-{count}")
        self.ids[page] = ids
        return ids

    def check_links(self, page):
        """Check the links a page writes itself, at their own line numbers."""
        for number, row in self.prose(page.read_text(encoding="utf-8")):
            bare = INLINE_CODE.sub("", row)
            targets = INLINE_LINK.findall(bare)
            reference = REFERENCE_LINK.match(bare)
            if reference:
                targets.append(reference.group(1))
            for link in targets:
                if not link or SCHEME.match(link) or link.startswith("/"):
                    continue
                path, _, fragment = link.partition("#")
                target = (page.parent / path).resolve() if path else page
                what = f"link ({link})"
                if target in self.generated and not target.exists():
                    continue
                if not target.exists():
                    self.error(page, number, what, f"no file at {self.label(target)}")
                    continue
                if not fragment or target.suffix != ".md" or target in self.generated:
                    continue
                if fragment.lower() not in self.heading_ids(target):
                    self.error(
                        page,
                        number,
                        what,
                        f"no heading with id '{fragment}' in {self.label(target)}",
                    )

    def run(self):
        pages = sorted(self.src.rglob("*.md"))
        for page in pages:
            self.page_text(page)
        for page in pages:
            self.check_links(page)
        return len(pages)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("src", type=Path)
    parser.add_argument("--generated", action="append", default=[])
    args = parser.parse_args()
    if not args.src.is_dir():
        print(f"docs-includes: {args.src} is not a directory", file=sys.stderr)
        return 2
    checker = Checker(args.src, args.generated)
    count = checker.run()
    if checker.errors:
        print("docs-includes: unresolved includes or links:", file=sys.stderr)
        for line in checker.errors:
            print(f"  {line}", file=sys.stderr)
        return 1
    print(f"docs-includes: ok, {count} pages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
