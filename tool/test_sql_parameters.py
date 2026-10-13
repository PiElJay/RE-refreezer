from pathlib import Path
import re, sqlite3
source = Path('lib/api/download.dart').read_text()
queries = re.findall(r"'([^']*SELECT[^']*title like \?)', \['%\$query%'\]", source)
assert len(queries) == 3, 'Offline searches must bind user input'
with sqlite3.connect(':memory:') as db:
    for table in ['Tracks', 'Albums', 'Playlists']:
        db.execute(f'CREATE TABLE {table} (id TEXT, title TEXT, offline INTEGER)')
        db.executemany(f'INSERT INTO {table} VALUES (?,?,?)', [('1', 'Safe song', 1), ('2', 'Other song', 0)])
    for query in queries:
        assert db.execute(query, ['%Safe%']).fetchall()
        assert not db.execute(query, ['%" OR 1=1 --%']).fetchall()
        assert not db.execute(query, ["%' OR 1=1 --%"]).fetchall()
assert 'tracks LIKE "%${t.id}%"' not in source
print('SQLite query-boundary checks passed: 9')
