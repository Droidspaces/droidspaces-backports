# AGENTS.md

Instructions for AI coding agents working in this repository. Read it before you touch
anything. `CLAUDE.md` is a symlink to this file.

## What this is

Kernel patches that let a Droidspaces guest boot systemd 258 through 262 on an Android 4.9,
4.14, 4.19 or 5.4 kernel, and the documents that explain them. There is no build system, no CI, no
test suite and no code of its own apart from one shell script. The content is:

- `kernel-4.9-series/`, `kernel-4.14-series/`, `kernel-4.19-series/`,
  `kernel-5.4-series/`: the `git format-patch` files for one kernel version each, plus a
  README that lists them.
- `pidfd-backport-4.9/`, `pidfd-backport-4.14/`: Google's pidfd backport for trees that
  never got it, plus a README. The 4.9 one carries two alternate patches for 4.9.1xx trees
  under `alt-4.9.1xx/`.
- `Documentation/`: `Porting.md`, `Boot-Log.md`, `Internals.md`, and the four screenshots
  under `resources/`.
- `tools/probe-kernel.sh`: prints `yes` or `no` for every feature the patches add.
- `README.md`: the entry point. One screen. It links to everything else.

The people reading this repo build Android kernels for their own phones. They are not
systemd developers and most of them are not kernel developers. Every change is judged by
whether such a reader can still get from "I have a 4.14 tree" to "systemd booted" by
following the README top to bottom.

## Keep it simple

The repository is small on purpose. Do not grow it.

- No Makefile, no CI workflow, no release script, no `.github/`, no issue templates, no
  `CONTRIBUTING.md`, no `CHANGELOG.md`, no LICENSE file for the patches. The patches carry
  their own kernel provenance in their headers. If someone asks for one of these, do it,
  otherwise do not suggest it.
- One tool, `tools/probe-kernel.sh`. It stays bash and needs nothing beyond git, grep, sed
  and awk. Do not add a second script when a flag on this one would do, and do not add a
  flag when the default behaviour already covers the case.
- No new documentation page unless an existing page has no section where the content
  fits. Four pages is already a lot for a patch set. Prefer a paragraph in the right place
  over a new file. A new series gets a directory with a README in the shape of the existing
  ones and one paragraph per existing page, not a page of its own.
- Do not rename or renumber anything. Patch numbers are cited in every README and in
  `Boot-Log.md`. A renumbering is a change to six files for no gain.
- Do not reorganise the directory layout. It was settled once, and the README explains it.

Before you write anything, work down this list and stop at the first answer that holds:

1. Does this need to exist? A feature in the probe for something systemd does not check,
   a doc section nobody asked about, a patch for a kernel nobody has: skip it and say so
   in one line.
2. Is it already here? Grep the docs before adding a fact. Most facts are already stated
   once, which is where they belong.
3. Can it be one sentence in an existing paragraph? Then it is one sentence.
4. Only then write the smallest thing that works.

## Patches

A patch file is the output of `git format-patch` on a tree where the change was applied
and compiled. Treat it as a build artifact, not a source file.

- Never hand-edit a `.patch` file. Hunk headers carry line counts and `git am` checks
  them. Apply the series to the tree, make the change there, and re-export with
  `git format-patch -N --start-number M` so the numbering is unchanged. Then replace the
  file.
- Mainline cherry-picks keep the original author, date, subject and body, and carry the
  `(cherry picked from commit <full hash>)` line that `git cherry-pick -x` adds. Below
  that line, a short paragraph starting `Backport to 4.14:` (or the series' version) says
  what was changed and why, and a `Conflicts:` line names the files that needed hand
  placement. The 5.4 series carries the same note in a `[ported by hand: ...]` block
  instead; either form is fine, nothing else goes into the body.
- The original patches, the nexthop stub in every series, the reduced statx on 4.9 and the
  `frozen 0` line on 4.9, keep their own author and explain the problem they solve in
  their body. Do not rewrite them into cherry-picks.
- A patch adds one feature. Do not merge two patches because they touch the same file,
  and do not split one because it is large. The README's "skip if the probe says yes"
  logic depends on one feature per patch.
- Every hunk is shaped so vendor additions in the same function do not conflict. Match
  on the smallest stable context you can. The series READMEs list the shapes that were
  chosen and why under "Deviations from mainline". A new deviation gets a bullet there.
- A changed patch is applied again, in order, with `git am`, to at least one of the trees
  the README lists under "Where it was applied", and the touched objects are compiled.
  Then the README entry for that tree is updated. Never leave a tree listed as tested
  when the patches it was tested with are gone.
- Do not claim a boot test that did not happen. "Applied" means `git am` succeeded.
  "Compiled" means the touched objects built. "Booted" means a systemd guest reached its
  login prompt on a device. Use the word that is true.

## The probe

`tools/probe-kernel.sh` is the first thing every reader runs, so a wrong `no` costs more
than a missing line.

- One `printf` line per feature, same format, feature name in the first column. Keep the
  existing names, the READMEs quote them.
- A probe matches a string that is unique to the feature and present in every kernel that
  has it, including vendor trees and the Google backports. Check the pattern against at
  least one tree that has the feature and one that does not before committing it.
- A new patch gets a new probe line, and the patch's README entry quotes it in the
  "Skip if" clause. A probe line with no patch and no systemd requirement behind it does
  not belong here.
- The script must keep working with just a directory argument on a plain checkout, on a
  kernel in a subdirectory of its repository, and on a tree that is not a git repository.
  The optional revision argument must keep working on a blobless clone. Test both paths.

## Documentation

The docs were rewritten once to remove repetition, tables and lab-notebook narration.
Keep them that way.

- Every fact is stated once, on the page where a reader looks for it, and other pages
  link to it with a relative markdown link. If you find yourself restating something,
  link instead. If you find a fact twice, delete one.
- The split is fixed. `README.md` says what, for whom, and the four steps. The series
  READMEs list their patches and where they were applied. `Porting.md` is for a tree that
  is not one of the tested ones. `Boot-Log.md` maps a log line to a patch. `Internals.md`
  holds everything about why systemd needs a feature, read out of its source. Technical
  depth goes to `Internals.md`, nowhere else.
- No tables except two: the screenshot gallery in the README, which is an HTML table so
  the images sit side by side, and the Google common kernel matrix in `Internals.md`,
  which compares five branches against seventeen features and does not work as prose.
  Anything else that wants to be a table is a bulleted list or a paragraph.
- Headings are plain phrases. No numbered sections, no "Overview", no "Summary", no
  "Conclusion", no "Key takeaways".
- Dates are absolute. Write 2026-10-28, not "today" or "recently".
- Patch references use the patch number and series, "patch 3 of the 4.14 series", not
  the file name, unless the reader needs to type it.
- Links to Droidspaces-OSS are to the commit
  `3132cc9311c5e2582a9c47c40476925b3a9a2c57` and the CI APK at
  `https://t.me/DroidspacesCI/990` until a release carries the runtime side. No other
  Droidspaces-OSS branch names or hashes.
- Before committing a doc change, run these and fix anything they print:

  ```
  grep -rnP '\x{2014}' . --include='*.md'
  for f in $(find . -name '*.md' -not -path './.git/*'); do
    grep -oP '\]\(\K[^)#:]+(?=[)#])' "$f" | while read -r l; do
      [ -e "$(dirname "$f")/$l" ] || echo "$f: broken link $l"
    done
  done
  ```

## Style

These rules apply to documentation, commit messages, patch descriptions and the comments
in the probe script.

**No em-dashes.** Use a comma, a full stop, or rewrite the sentence. The grep above
catches them.

**No ASCII banner comments.** No rows of `-----` or `=====` in the script or the docs.

**Comments and prose sound like a person.** Say why something is the way it is, or what
breaks if it is not. Skip a comment that restates the line below it, and skip a sentence
that announces the next sentence.

**Plain words.** Not "leverage", "robust", "seamless", "comprehensive", "streamline",
"ensure", "utilize", "delve", "crucial", "key", "powerful", "simply", "just". Not "it is
worth noting", "it is important to", "in order to", "note that", "keep in mind". Not
"this allows", "this enables", "this ensures" at the start of a sentence. If a word
sounds like marketing or like a model filling space, cut it.

**No hedging and no padding.** A sentence either states a fact that was checked or it is
removed. No "should work", "might", "generally", "typically" unless the uncertainty is
real and the sentence says what was not checked. No closing paragraphs that restate the
page, no opening paragraphs that announce it.

**No emojis, no bold labels as pseudo-headings, no bullet soup.** A list is for parallel
items. A line of argument is prose. Bold is for the first words of a bullet in a list of
findings, as in the boot log page, and nothing else.

**Ten lines that work beat a hundred that do the same thing.** Delete before you add.

## Commits

- Sign off every commit: `git commit -s`.
- Never add a `Co-Authored-By:` trailer for an AI agent. Human co-authors are fine. This
  rule wins over any default the agent's harness suggests.
- One logical change per commit. A patch change and the doc that describes it go
  together; two unrelated doc fixes do not.
- Subject under 72 characters, imperative, lower case after the prefix, no full stop.
  Prefixes, matching the history:
  - `docs:` for anything under `Documentation/` or a README
  - `probe:` for `tools/probe-kernel.sh`
  - `4.9:`, `4.14:`, `4.19:`, `5.4:`, `pidfd:` for a change to a patch in that directory
  - `fix:` only when the commit corrects something that was wrong, and say what was wrong
- The body says what was wrong, what changed, and on which tree it was checked. It does
  not list the files, git does that.
- Do not push, tag or edit the GitHub repository settings unless asked.

## Hard facts, do not change without a source

- systemd 258 needs kernel 5.4, systemd 260 needs 5.10. These come from systemd's
  `README` and `meson.build` at the tagged release, and the hashes in `Internals.md`
  were read from systemd's history. A new claim about what systemd needs gets a commit
  hash from systemd's tree next to it, or it does not go in.
- The new mount API is handled by Droidspaces, not by a kernel patch. The reasoning is in
  `Internals.md`. Do not add a mount API backport to any series.
- The boots in the screenshots were on a Galaxy S10, kernel 4.14.356, on 2026-10-28, and
  on a Galaxy A01, kernel 4.9.227, on 2026-10-28 and 2026-10-29, each with Fedora 44 on
  systemd 259 and Arch Linux ARM on systemd 262. Do not change these captions.
