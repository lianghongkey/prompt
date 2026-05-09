# Hybrid Input Model (混合输入模型)

This document describes the segmentation and matching model that drives Mandarin
candidate generation. It replaces a previous heuristic that handled "full pinyin"
and "pure-initial shortcut" as two disjoint code paths and could not handle
inputs that mix the two.

## Motivation

Before this change, `zmyan` could not produce 怎么样:

- `PinyinSegmentor.segment("zmyan")` failed because no leading prefix was a
  complete syllable, so no scheme covered the whole input.
- The fallback `extractInitialsFromUnsegmented` walked left-to-right and counted
  every consonant as a syllable initial, treating the trailing `n` of `yan` as a
  separate syllable. The shortcut intercode became `[z, m, y, n]` (four
  initials), missing 怎么样's stored shortcut `zmy` (three initials).

The same class of failure hit any input that mixed initials with a trailing
multi-letter pinyin token: `zmyang`, `wsmyao`, `nhao`, `nshj` etc.

The model below treats the two existing input styles as special cases of a
single, more general scheme.

## Token model

A segmentation scheme is a list of `SegmentToken`s. Each token has a kind:

- **`.full`** — `text` is a complete syllable in `pinyinsyllabletable`. `origin`
  is its canonical form (e.g. `lue` → `lve`).
- **`.abbrev`** — `text` is one of the 23 valid pinyin initials:
  `b p m f d t n l g k h j q x r z c s y w` (single letter), or `zh ch sh`
  (two letters). `origin == text`. Stands for "any syllable starting with
  these letters".

Notes:
- `a o e` and the multi-letter zero-initial syllables `an ai ang ao en ei eng er
  o ou ng` are always `.full` (they are complete syllables in the table). They
  are never `.abbrev`.
- `i u v` are neither valid abbrevs nor full syllables. Inputs containing only
  these letters at a position cannot segment at that position.

## Segmentation algorithm

`PinyinSegmentor.segment(text:)` enumerates every full-coverage scheme via
recursive descent with memoization. At each starting position it tries every
prefix length (1..6) and admits two kinds of split:

- The prefix is a syllable in the DB → emit a `.full` token, recurse on the
  remainder.
- The prefix is in `validAbbrevs` (1- or 2-letter initial) AND is not also a
  full syllable → emit a `.abbrev` token, recurse on the remainder.

For example `zmyan` produces the schemes (truncated):

```
[z·abbrev, m·abbrev, yan·full]
[z·abbrev, m·abbrev, y·abbrev, an·full]
[z·abbrev, m·abbrev, y·abbrev, a·full, n·abbrev]
```

### Ranking

Schemes are sorted by `(count, abbrevCount, lex)`:

1. fewer tokens first — more grouped means less ambiguity;
2. fewer `.abbrev` tokens — more concrete information;
3. lexicographic tiebreaker on token kinds (full before abbrev at the leftmost
   differing position).

The first scheme is the best (`segmentation.first`). For `zmyan` the winner is
`[z, m, yan]` with quality `(3, 2)`.

`Engine` queries every scheme that ties on `(count, abbrevCount)`. This keeps
the existing behavior where alternate equally-good segmentations
(`gen+gao+xiao` vs `geng+ao+xiao`) both contribute candidates.

### Caches

- `syllableCache: [Int: String]` — caches `pinyinsyllabletable` lookups by
  charcode. Invariant: ~400 entries, never grows. Negative results are cached
  as empty strings.
- `schemeCache: [String: Segmentation]` — caches whole-segmentation results
  keyed by raw input. FIFO-evicted at 256 entries. Hit rate is high during
  typing because adjacent keystrokes share prefixes.

Call `PinyinSegmentor.resetCaches()` after settings that affect segmentation
change (e.g. fuzzy pinyin toggle).

## Matching algorithm

A scheme is checked against a stored `pinyin` (space-separated syllables) by
running a per-position test that **differs by token kind**:

- `.abbrev` token: prefix match.
  ```
  syllable.hasPrefix(token.text)
  ```
  Prefix is the whole point of an abbrev token (`z` matches `zen`, `zhong`;
  `zh` matches `zhong`).

- `.full` token: equality against `token.origin` (the canonical syllable).
  ```
  syllable == token.origin
  ```
  Prefix on `.full` is **forbidden**: `ne` is a complete syllable and must
  not silently extend to `neng`.

If `FuzzyPinyinSettings.isAnyEnabled`, both rules are augmented with fuzzy
expansion. For abbrev: the syllable's fuzzy variants are also tried as prefix
targets (so `z` matches a stored `zhong` via `zh↔z`). For full: equality is
checked under fuzzy expansion of either side (so `in` matches a stored
`ing`-syllable when `in/ing` fuzzy is on; `yan` matches `yang` when `an/ang`
fuzzy is on).

### Sequential typo correction interplay

`PinyinSegmentor` also expands the input through enabled `TypoCorrection`
rules (currently `gn → ng`). Each corrected variant is segmented separately
and the resulting tokens are remapped so `text` keeps the original chars and
`origin` is the canonical syllable. All resulting schemes — including ones
where the swapped pair straddles a syllable boundary — are kept; the matching
algorithm above filters out incorrect interpretations. Concretely, typing
`liagne` produces both `[liang, e]` (swapped pair inside `liang`) and
`[lian, ge]` (swapped pair straddling lian|ge); the strict `.full` rule
ensures only legitimate `lian ge` words (恋歌/连个/练个) and tail-drop single
chars (两/亮/凉) surface — never 两根 (liang gen), because `gen ≠ ge` and
`liang ≠ lian` without `ian/iang` fuzzy.

### Why prefix-on-full was removed

A previous version allowed `.full` tokens to also prefix-match (so a user-typed
full syllable like `yan` would extend to `yang`). That sounded harmless on its
own but compounded badly with fuzzy:

- `gonne` with `on/ong` fuzzy → `gon` resolves to `gong` (full token).
- ping `"gong ne"` finds nothing → fall through to shortcut+prefix.
- Old rule: `"neng".hasPrefix("ne") == true` → 功能 (gong neng) surfaces.
- Every token got "brain-expanded" twice — once by fuzzy, once by prefix.

The new rule (full = equality-or-fuzzy) restricts each token to a single layer
of correction. The user must opt into near-miss matching by enabling the
relevant fuzzy rule, instead of getting it via an always-on prefix shortcut.

## Database query strategy

Two query paths are used:

### Ping path (fast)

When **every** token is `.full`, the engine first tries `pinyintable.ping = ?`
where `?` is the deterministic hash of the space-joined canonical pinyin. This
is an indexed B-tree lookup, instant for the common "user typed the full
pinyin" case.

### Shortcut + filter path (general)

Used when the scheme has any `.abbrev` token, or as a fallback when the
all-full ping path returns no rows. Note: for an all-full scheme the
fall-through is now mostly a safety net — under the new tokenMatches rule
each `.full` token requires equality, so the shortcut path can only surface
rows whose every full-token slot equals (or is fuzzy-equivalent to) the typed
syllable. The interesting cases are hybrid schemes with abbrevs in the
leading positions and a full token at the tail (e.g. `[z, m, yang]`).

1. Compute the shortcut intercode by taking the first character of each token
   (`schemeShortcutCode`). This matches how `pinyintable.shortcut` is stored
   (combined intercode of each syllable's first letter).
2. Query `pinyintable WHERE shortcut = ? LIMIT 1000`.
3. For each row, split `pinyin` by space and filter:
   - the row's `word.count` must equal the scheme's token count;
   - for each `(token, syllable)` pair, run `tokenMatches` (kind-aware:
     prefix for abbrev, equality-or-fuzzy for full).
4. Cap the survivors at 200 to keep the candidate list bounded.

The legacy single-initial-only `pinyin.hasPrefix(text)` post-filter and the
`extractInitialsFromUnsegmented` walk are gone; both their responsibilities are
subsumed by the per-token rule above.

### Tail-drop fallback

After querying the top-quality schemes, the engine drops the trailing token of
each top scheme and re-queries the truncated scheme. This produces single-char
candidates (and shorter prefix matches) needed to enter Word Creation mode.

For `[z, m, yan]`:
- drop yan → `[z, m]` → shortcut `zm` → 2-syllable z·m words
- drop m  → `[z]` → shortcut `z` → 1-syllable z words

## UserLexicon

`UserLexicon.suggest` mirrors the same model:

- A direct `text → ping` lookup catches stored entries where the user typed the
  exact pinyin form already in the DB.
- For each top-quality scheme, the all-full ping fast path runs first. All-full
  schemes never fall through to shortcut+filter — see CLAUDE.md "runScheme
  Early-Return Invariant". Hybrid schemes (with abbrev tokens) go straight to
  shortcut+filter, applying the kind-aware `tokenMatches`.
- Tail-drop fallback runs for schemes of length ≥ 3.

A latent bug was fixed in passing: the previous shortcut lookup hashed
`text.replacingOccurrences(of: "y", with: "j")` while the storage path
hashed the unmodified first letters via `String.shortcut`. The two never
matched, so the shortcut lookup never found anything.

The `userlexicontable.shortcut` is unchanged on disk — it stores
`romanization.shortcut`, the deterministic hash of the joined first letters of
each space-separated syllable. The new lookup recomputes the same hash from
the scheme's per-token first letters, so existing rows are matched correctly.

## Cross-reference filter

`PromptInputController.filterCandidates` finds a "common token" between the
buffer scheme and the filter scheme. With hybrid tokens, two tokens overlap if
some real syllable would be accepted by both predicates:

| buffer × filter | overlap rule |
| --- | --- |
| full × full | fuzzy expansions intersect |
| full × abbrev | some fuzzy variant of full starts with abbrev's letters |
| abbrev × full | some fuzzy variant of full starts with abbrev's letters |
| abbrev × abbrev | one's text is a prefix of the other (covers `z` vs `zh`) |

The "allowed character" extraction at the common position uses the same per-
token rule (full → equality-or-fuzzy, abbrev → prefix-or-fuzzy). With this,
filter inputs may now be abbreviated: typing buffer=`xiguan` then holding
shift to type filter=`cmh` works the same way as the previous-supported
`chenmingmu`-style full-pinyin filters.

## Word Creation

Word Creation activates when the user picks a single character whose
`candidate.input.count` is less than the buffer length, leaving residual
buffer to compose the rest of the word.

In the hybrid model:
- top-quality scheme candidates have `input = scheme.map(\.text).joined()`,
  the full input. Selecting them commits the whole buffer.
- single-char candidates from the tail-drop fallback have `input = first
  token's text`. Selecting them consumes only that prefix.
- For `[z, m, yan]`, the fallback chain produces single-char candidates with
  `input = "z"`, `"zm"` etc. Choosing 怎 with `input = "z"` leaves `myan` in
  the buffer, which re-segments to `[m, yan]` for the next selection.

The composed word's romanization (used for `UserLexicon` storage) is the
joined per-step romanizations, so it matches the canonical full-pinyin form
even though the user typed an abbreviated input.

## Behavior change summary

### Newly supported

- Mixed initials + full syllable inputs, in any position:
  - `zmyang` → 怎么样
  - `wsmyao` → 为什么要
  - `nhao` → 你好
  - `jrlmsx` → 今日来买什么 (etc.)
- Single-letter `.abbrev` candidates can now act as the first token. Typing
  just `z` produces all single-character z-syllable words.
- Cross-reference filter accepts abbreviated filter text.
- UserLexicon shortcut lookup actually finds entries (latent y→j hash bug
  fixed).
- Near-miss full-pinyin (`zmyan` / `zenmeyan` for 怎么样, where the user
  intended `yang` but typed `yan`) requires the user to enable the
  corresponding fuzzy rule (`an/ang`). The previous always-on prefix
  extension was removed because it produced compound noise with fuzzy on
  other tokens. See `### Why prefix-on-full was removed` above.

### Changed semantics

- `PinyinSegmentor.maxSyllableCount` returns the true scheme token count, not
  a heuristic consonant-cluster estimate. For inputs where the trailing
  characters were not a real syllable (e.g. `liangho`), the new count reflects
  full segmentation: `[liang, h, o]` = 3 (was 2 under the heuristic).
- A `.full` token does **equality** matching (modulo fuzzy), not prefix
  matching, in the shortcut+filter path. `zenmeyan` no longer silently
  surfaces 怎么样 (yang) — the user must enable `an/ang` fuzzy. Exact
  full-pinyin input still gets exact results via the ping fast path.

### Removed

- `Engine.extractInitials`, `Engine.extractInitialsFromUnsegmented` (subsumed
  by hybrid scheme).
- `Engine.pinyinShortcutInternal` (replaced by `shortcutSchemeQuery`).
- `Engine.generateCorrectedInputs` (was a workaround for segmentation gaps
  the new model does not have).
- The y→j substitution in `UserLexicon.query` (latent bug).

## Performance notes

- Segmentation is O(n²) in input length in the worst case (memoized DFS over
  start positions) but bounded by `results.count > 200` per branch and the
  segmentation length cap. Real Mandarin input rarely exceeds 12 characters.
- Shortcut path queries `LIMIT 1000` rows then filters in Swift. For the most
  popular shortcut codes (`wsm`, `zmy`, etc.) the DB has ~150–400 rows; LIMIT
  1000 leaves headroom for filtering without missing the frequency-leader
  rows.
- Per-row prefix filtering is short-circuited at the first failing token,
  so most rows reject in one comparison.
- Caches: `syllableCache` (~400 entries), `schemeCache` (FIFO 256). Both are
  process-wide.

## Test matrix

`CoreIMETests/CoreIMETests.swift` covers:

- Full-pinyin regressions: `putonghuapinyin`, `gengaoxiao` two-way ambiguity,
  `zhidao` ordering.
- Hybrid acceptance: `zmyang`/`wsmyao`/`nhao` produce the expected Chinese
  word with no fuzzy enabled (full token matches the canonical syllable
  exactly).
- Token-count invariants: `zmyan` is 3 tokens, `zmyang` is 3 tokens, partial
  `zmya` is 3 tokens.
- Token-kind invariants: `a/o/e/an/ang/en/eng/ao/ng` are full; pure initials
  `b/p/.../zh/ch/sh` are abbrev.
- Single-char fallback: `zhidao` surfaces both 知道 and 知.
- Near-miss requires fuzzy: `zmyan` and `zenmeyan` only surface 怎么样 when
  `an/ang` fuzzy is enabled; without fuzzy they don't.
- Compound-extension regression: `gonne` with `on/ong` fuzzy must NOT
  surface 功能 (gong neng) — `ne` is a complete syllable and shall not
  silently extend to `neng`.
- Typo-correction inclusiveness: `liagne` with `gn → ng` enabled produces
  both `[liang, e]` and `[lian, ge]` schemes; `lian ge` words (恋歌/连个)
  surface, while 两根 (liang gen) is still suppressed by the strict full
  rule.
- Exact-first ranking: `zenme` puts 怎么 at the top of the candidate list.
- Single-letter syllable set: only `a/e/o` are full single-letter syllables;
  `b/n/z/y` are abbrev; `i/u/v` cannot segment.

Run with `cd CoreIME && swift test`.

## Files touched

- `CoreIME/Sources/CoreIME/PinyinSegmentor.swift` — new hybrid algorithm,
  `SegmentToken.kind`, scheme ranking, caches.
- `CoreIME/Sources/CoreIME/Engine.swift` — `pinyinSuggestMulti` rewritten;
  introduces `runScheme`, `shortcutSchemeQuery`, `tokenMatches`,
  `schemeShortcutCode`. Old shortcut/initials helpers removed.
- `Prompt/UserLexicon.swift` — `suggest` rewritten to mirror Engine; removes
  y→j hash bug; bumps prepared-statement LIMITs.
- `Prompt/PromptInputController.swift` — cross-reference filter updated to
  accept hybrid common-token matching.
- `CoreIME/Tests/CoreIMETests/CoreIMETests.swift` — full hybrid test matrix.
