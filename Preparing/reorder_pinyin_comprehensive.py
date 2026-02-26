#!/usr/bin/env python3
"""
Reorder pinyin.txt by real word frequency using jieba's corpus data (~500K entries).

Tier system (lower score = higher priority):
  1. Single chars with jieba freq  → rank 1..~10530
  2. Multi-char words with jieba freq → 10000 + rank (length-adjusted)
  3. Single chars NOT in jieba → 100000
  4. Multi-char words NOT in jieba → estimated from component char freqs + length penalty

Same word with different pinyin readings are grouped together, preserving original relative order.
Exact duplicate (word, pinyin) entries are removed.
Stable sort: identical scores preserve original file order.
"""

import math
import sys
from pathlib import Path

import jieba


def main():
    pinyin_path = Path(__file__).parent / "Sources" / "Preparing" / "Resources" / "pinyin.txt"
    if not pinyin_path.exists():
        print(f"Error: {pinyin_path} not found", file=sys.stderr)
        sys.exit(1)

    # Initialize jieba frequency dictionary
    print("Initializing jieba...")
    jieba.initialize()
    freq = jieba.dt.FREQ
    print(f"  jieba entries: {len(freq)}")

    # Build per-character frequency lookup
    char_freqs = {}
    for word, f in freq.items():
        if len(word) == 1 and f > 0:
            char_freqs[word] = f

    # Read all entries, deduplicating exact (word, pinyin) pairs
    print(f"Reading {pinyin_path}...")
    entries = []
    seen = set()
    duplicates = 0
    with open(pinyin_path, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                continue
            word, pinyin, charcode, hash_val = parts
            key = (word, pinyin)
            if key in seen:
                duplicates += 1
                continue
            seen.add(key)
            entries.append((word, pinyin, charcode, hash_val, i))

    original_count = len(entries) + duplicates
    print(f"  {original_count} lines read, {duplicates} duplicates removed, {len(entries)} unique entries")

    # --- Rank single chars by jieba frequency (descending) ---
    char_best_freq = {}
    for word, pinyin, charcode, hash_val, orig_idx in entries:
        if len(word) == 1 and word in freq and freq[word] > 0:
            char_best_freq[word] = max(char_best_freq.get(word, 0), freq[word])

    sorted_chars = sorted(char_best_freq.items(), key=lambda x: -x[1])
    char_rank = {word: rank + 1 for rank, (word, _) in enumerate(sorted_chars)}
    print(f"  Single chars with jieba freq: {len(char_rank)}")

    # --- Rank multi-char words by jieba frequency (descending) ---
    multi_best_freq = {}
    for word, pinyin, charcode, hash_val, orig_idx in entries:
        if len(word) > 1 and word in freq and freq[word] > 0:
            multi_best_freq[word] = max(multi_best_freq.get(word, 0), freq[word])

    sorted_multi = sorted(multi_best_freq.items(), key=lambda x: -x[1])
    multi_rank = {word: rank + 1 for rank, (word, _) in enumerate(sorted_multi)}
    print(f"  Multi-char words with jieba freq: {len(multi_rank)}")
    # --- Scoring function ---
    max_freq = max(freq.values())  # ~883634

    def compute_score(word):
        wlen = len(word)
        if wlen == 1:
            if word in char_rank:
                return float(char_rank[word])  # Tier 1: 1..~10530
            else:
                return 100000.0  # Tier 3: rare single chars
        else:
            if word in multi_rank:
                # Tier 2: 10000 + rank, slight penalty for longer words
                rank = multi_rank[word]
                length_factor = 1.0 + (wlen - 2) * 0.1
                return 10000.0 + rank * length_factor
            else:
                # Tier 4: estimate from component character frequencies
                char_f = []
                for ch in word:
                    cf = char_freqs.get(ch, 0)
                    char_f.append(cf if cf > 0 else 1)
                geo_mean = math.exp(sum(math.log(f) for f in char_f) / len(char_f))
                # Higher geo_mean (common chars) → lower score
                score = 200000.0 + (1.0 - geo_mean / max_freq) * 800000.0
                # Length penalty: longer words sink further
                score += (wlen - 2) * 50000.0
                return score

    # --- Group entries by word, compute group scores ---
    print("Computing scores and sorting...")
    word_groups = {}
    word_order = {}  # track first occurrence order per word
    for word, pinyin, charcode, hash_val, orig_idx in entries:
        if word not in word_groups:
            word_groups[word] = []
            word_order[word] = orig_idx
        word_groups[word].append((pinyin, charcode, hash_val, orig_idx))

    scored_groups = []
    for word, readings in word_groups.items():
        score = compute_score(word)
        first_idx = word_order[word]
        scored_groups.append((score, first_idx, word, readings))

    # Stable sort by (score, original first occurrence)
    scored_groups.sort(key=lambda x: (x[0], x[1]))
    # --- Write output ---
    output_lines = []
    for score, _, word, readings in scored_groups:
        # Preserve original relative order within readings of same word
        readings.sort(key=lambda x: x[3])
        for pinyin, charcode, hash_val, _ in readings:
            output_lines.append(f"{word}\t{pinyin}\t{charcode}\t{hash_val}")

    with open(pinyin_path, "w", encoding="utf-8") as f:
        for line in output_lines:
            f.write(line + "\n")

    print(f"\nWrote {len(output_lines)} entries to {pinyin_path}")
    print(f"Removed {duplicates} duplicates")

    # --- Verification ---
    print("\nTop 50 entries:")
    for i, line in enumerate(output_lines[:50]):
        parts = line.split("\t")
        print(f"  {i+1:3d}. {parts[0]} ({parts[1]})")

    # Spot-check: single-char "shi" readings
    print("\nSingle-char 'shi' entries (in order):")
    for i, line in enumerate(output_lines):
        parts = line.split("\t")
        if len(parts[0]) == 1 and parts[1] == "shi":
            print(f"  #{i+1}: {parts[0]}")
        if i > 20000:
            break


if __name__ == "__main__":
    main()
