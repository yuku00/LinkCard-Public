"""Synthetic format/SQL sanity tests only: DOES NOT execute or compile Swift."""
from pathlib import Path
import base64
import gzip
import re
import sqlite3
import tempfile

root = Path(__file__).resolve().parents[1]
swift = (root / 'Tests/AppleNotesTests.swift').read_text()
blob = base64.b64decode(re.search(r'base64Encoded: "([A-Za-z0-9+/=]+)"', swift)[1])

def field(data, wanted):
    offset = 0
    found = None
    def varint():
        nonlocal offset
        value = 0
        for i in range(10):
            if offset >= len(data):
                raise ValueError('truncated')
            b = data[offset]
            offset += 1
            if i == 9 and b > 1:
                raise ValueError('overflow')
            value |= (b & 127) << (7 * i)
            if not b & 128:
                return value
        raise ValueError('overflow')
    while offset < len(data):
        key = varint()
        number, wire = key >> 3, key & 7
        if not 0 < number <= 536870911 or number == wanted and wire != 2:
            raise ValueError('key')
        if wire == 0:
            varint()
            n = 0
        elif wire == 1:
            n = 8
        elif wire == 2:
            n = varint()
        elif wire == 5:
            n = 4
        else:
            raise ValueError('wire')
        if n > len(data) - offset:
            raise ValueError('length')
        if number == wanted:
            if found is not None:
                raise ValueError('duplicate')
            found = data[offset:offset+n]
        offset += n
    if found is None:
        raise ValueError('missing')
    return found

assert field(field(field(gzip.decompress(blob), 2), 3), 2).decode() == '合成正文\n第二行 😀\n\ufffc'
for bad in (b'\x00', b'\x12\x80', b'\x12\x00\x12\x00', b'\x12' + b'\xff'*9 + b'\x02'):
    try:
        field(bad, 2)
    except ValueError:
        pass
    else:
        raise AssertionError('malformed protobuf accepted')

# Run the SELECT copied directly from the Swift source with identical bindings.
store = (root / 'Sources/AppleNotesStore.swift').read_text()
sql = re.search(r'let sql = """\n(.*?)\n        """', store, re.S)[1]
protected = 'COALESCE(o.ZISPASSWORDPROTECTED,0) != 0 OR d.ZCRYPTOTAG IS NOT NULL'
sql = sql.replace('\\(protected)', protected).replace('\\(deleted)', 'COALESCE(o.ZMARKEDFORDELETION,0)').replace('\\(AppleNoteBody.limit)', str(2*1024*1024))
assert '\\(' not in sql
with tempfile.TemporaryDirectory(prefix='synthetic-notes-') as directory:
    path = Path(directory) / 'NoteStore.sqlite'
    writer = sqlite3.connect(path)
    writer.executescript('''PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;
    CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZISPASSWORDPROTECTED INTEGER, ZMARKEDFORDELETION INTEGER);
    CREATE TABLE ZICNOTEDATA (ZNOTE INTEGER, ZDATA BLOB, ZCRYPTOTAG BLOB);''')
    writer.executemany('INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (?,?,?,?)', [(1,'Synthetic',0,0),(2,'Locked',1,0),(3,'Deleted',0,1),(4,'Missing',0,0),(5,'Broken',0,0),(6,'Encrypted',0,0)])
    writer.executemany('INSERT INTO ZICNOTEDATA VALUES (?,?,?)', [(1,blob,None),(2,blob,None),(3,blob,None),(4,None,None),(5,b'bad',None),(6,blob,b'tag')])
    writer.commit()
    original = path.read_bytes(), Path(str(path)+'-wal').read_bytes()
    reader = sqlite3.connect(path.as_uri()+'?mode=ro', uri=True)
    reader.execute('BEGIN')
    reader.execute('PRAGMA page_count').fetchone()
    memory = sqlite3.connect(':memory:')
    reader.backup(memory, pages=128)
    memory.execute('PRAGMA query_only=ON')
    rows = memory.execute(sql).fetchall()
    assert len(rows) == 6 and rows[0][4] == blob
    assert rows[1][0] == '' and rows[1][1] == 1 and rows[1][4] is None
    assert rows[2][2] == 1 and rows[2][4] is None
    assert rows[3][3] is None
    assert rows[4][4] == b'bad'
    assert rows[5][1] == 1 and rows[5][4] is None
    assert (path.read_bytes(), Path(str(path)+'-wal').read_bytes()) == original
    memory.close()
    reader.rollback()
    reader.close()
    writer.close()
print('PASS: synthetic gzip/protobuf fixture, malformed inputs, actual Swift SELECT, read-only WAL backup, DB/WAL unchanged')
print('NOT RUN: Swift code/XCTest/iOS permissions; Python format checks are not a Swift test substitute')
