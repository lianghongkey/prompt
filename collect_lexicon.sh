#!/bin/bash
# Merge user lexicon from the sandboxed container into a local collection file.
# Usage: ./collect_lexicon.sh

SOURCE="/Users/colin/Library/userlexicon.sqlite3"
TARGET="$(dirname "$0")/userlexicon.sqlite3"

if [ ! -f "$SOURCE" ]; then
        echo "Source not found: $SOURCE"
        exit 1
fi

# Create target table if it doesn't exist
sqlite3 "$TARGET" "CREATE TABLE IF NOT EXISTS userlexicontable(id INTEGER NOT NULL PRIMARY KEY, frequency INTEGER NOT NULL, word TEXT NOT NULL, romanization TEXT NOT NULL, shortcut INTEGER NOT NULL, ping INTEGER NOT NULL);"

# Attach source and merge: keep the higher frequency for existing entries, insert new ones
sqlite3 "$TARGET" <<'SQL'
ATTACH DATABASE '' AS src;
-- Use a temp file so we can load the source safely
DETACH DATABASE src;
SQL

sqlite3 "$TARGET" "ATTACH '${SOURCE}' AS src;
UPDATE userlexicontable
SET frequency = (SELECT s.frequency FROM src.userlexicontable s WHERE s.id = userlexicontable.id)
WHERE id IN (SELECT s.id FROM src.userlexicontable s WHERE s.frequency > userlexicontable.frequency);

INSERT OR IGNORE INTO userlexicontable (id, frequency, word, romanization, shortcut, ping)
SELECT id, frequency, word, romanization, shortcut, ping FROM src.userlexicontable;

DETACH DATABASE src;"

COUNT=$(sqlite3 "$TARGET" "SELECT COUNT(*) FROM userlexicontable;")
echo "Done. Total entries in collection: $COUNT"
