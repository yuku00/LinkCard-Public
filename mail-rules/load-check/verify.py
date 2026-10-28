#!/usr/bin/env python3
"""Strict, dependency-free audit of this load-only Mach-O (not a Mail runtime test)."""
import hashlib
import json
import pathlib
import struct
import sys


def require(ok, message):
    if not ok:
        raise ValueError(message)


def u32(data, offset, endian='<'):
    return struct.unpack_from(endian + 'I', data, offset)[0]


def name(raw):
    return raw.split(b'\0', 1)[0].decode('ascii')


def audit_slice(d, arch):
    require(u32(d, 0) == 0xfeedfacf, 'not 64-bit little-endian Mach-O')
    cpu, subtype, kind, count, size = struct.unpack_from('<5I', d, 4)
    require(cpu == 0x100000c and (subtype & 0xff) == {'arm64': 0, 'arm64e': 2}[arch], 'wrong CPU')
    require(kind == 6, 'not MH_DYLIB')
    p = 32
    sections, deps, ids, sigs, builds, symbols = {}, [], [], [], [], []
    symtab = None
    for _ in range(count):
        cmd, n = struct.unpack_from('<II', d, p)
        require(n >= 8 and p + n <= 32 + size, 'load command bounds')
        if cmd in (0xc, 0xd, 0x80000018, 0x8000001f, 0x80000023):
            text = name(d[p + u32(d, p + 8):p + n])
            (ids if cmd == 0xd else deps).append(text)
            if cmd != 0xd:
                require(cmd == 0xc, 'unexpected optional/reexport dependency')
        elif cmd == 0x19:
            for i in range(u32(d, p + 64)):
                q = p + 72 + i * 80
                sname, seg = name(d[q:q+16]), name(d[q+16:q+32])
                addr, length, offset = struct.unpack_from('<QQI', d, q + 32)
                require(sname not in sections, 'duplicate section')
                sections[sname] = (addr, length, offset, seg)
                require('objc' not in sname.lower(), 'Objective-C section')
        elif cmd == 2:
            symtab = struct.unpack_from('<4I', d, p + 8)
        elif cmd == 0x1d:
            sigs.append(struct.unpack_from('<II', d, p + 8))
        elif cmd == 0x32:
            builds.append(struct.unpack_from('<III', d, p + 8))
        elif cmd in (0x8000001c, 0xe, 0xf):
            raise ValueError('unexpected rpath/dylinker command')
        p += n
    require(p == 32 + size, 'load command size mismatch')
    require(ids == ['@rpath/MailLoadCheck.dylib'], 'wrong install name')
    require(deps == ['/usr/lib/libSystem.B.dylib'], 'unexpected dependencies: ' + repr(deps))
    require(len(builds) == 1 and builds[0][:2] == (2, 0x100600), 'not iOS min 16.6')
    require(symtab is not None, 'missing symbol table')
    symoff, nsym, stroff, strsize = symtab
    for i in range(nsym):
        strx, stype, sect, desc, value = struct.unpack_from('<IBBHQ', d, symoff + i * 16)
        text = name(d[stroff + strx:stroff + strsize])
        require((stype & 0x0e) != 0, 'undefined symbol: ' + text)
        require(not (stype & 1), 'unexpected external symbol: ' + text)
        symbols.append((text, value))
    require({s[0] for s in symbols} == {'_MailLoadCheckInit', '_MailLoadCheckVersion'}, 'unexpected symbols')
    textaddr, textsize, textoff, _ = sections['__text']
    require(textsize == 4 and d[textoff:textoff+4] == bytes.fromhex('c0035fd6'), 'constructor must contain only ret')
    require(dict(symbols)['_MailLoadCheckInit'] == textaddr, 'constructor symbol mismatch')
    require('__mod_init_func' in sections and '__init_offsets' not in sections, 'constructor section mismatch')
    _, initsize, initoff, _ = sections['__mod_init_func']
    require(initsize == 8 and struct.unpack_from('<Q', d, initoff)[0] == textaddr, 'constructor pointer mismatch')
    require(b'MailLoadCheck 0.1.0 | TrollFools native load-only control\0' in d, 'missing immutable version')
    require(len(sigs) == 1, 'expected one code signature')
    sigoff, sigsize = sigs[0]
    sig = d[sigoff:sigoff+sigsize]
    require(u32(sig, 0, '>') == 0xfade0cc0, 'bad signature SuperBlob')
    total, num = struct.unpack_from('>II', sig, 4)
    require(total <= sigsize, 'signature bounds')
    cds = []
    for i in range(num):
        slot, off = struct.unpack_from('>II', sig, 12 + i * 8)
        magic, length = struct.unpack_from('>II', sig, off)
        require(off + length <= total, 'signature blob bounds')
        require(slot not in (5, 7), 'entitlements are not allowed')
        if magic != 0xfade0c02:
            require(slot == 2 and magic == 0xfade0c01, 'unexpected signature blob')
            continue
        cd = sig[off:off+length]
        version, flags, hashoff, identoff, special, slots, limit = struct.unpack_from('>7I', cd, 8)
        hashsize, hashtype, platform, pagebits = struct.unpack_from('4B', cd, 36)
        require(flags & 2, 'signature must be ad-hoc')
        require(limit == sigoff, 'CodeDirectory must cover full unsigned Mach-O')
        require(hashtype in (1, 2, 4), 'unsupported hash type')
        digest = {1: hashlib.sha1, 2: hashlib.sha256, 4: hashlib.sha384}[hashtype]
        require(hashsize == digest().digest_size, 'hash width mismatch')
        require(0 < pagebits <= 16, 'unexpected page size')
        pagesize = 1 << pagebits
        require(slots == (limit + pagesize - 1) // pagesize, 'page count mismatch')
        for j in range(slots):
            expected = digest(d[j * pagesize:min((j+1) * pagesize, limit)]).digest()
            require(cd[hashoff+j*hashsize:hashoff+(j+1)*hashsize] == expected, 'CodeDirectory page hash mismatch')
        for entitlement_slot in (5, 7):
            if special >= entitlement_slot:
                h = cd[hashoff-entitlement_slot*hashsize:hashoff-(entitlement_slot-1)*hashsize]
                require(h == bytes(hashsize), 'unexpected entitlement hash')
        cds.append({'hash_type': hashtype, 'cdhash': digest(cd).digest()[:20].hex(), 'pages_verified': slots})
    require(cds, 'missing CodeDirectory')
    return {'arch': arch, 'install_name': ids[0], 'dependencies': deps, 'min_os': '16.6',
            'constructor': 'one __mod_init_func pointer; one ret instruction; no stores/calls',
            'imports': [], 'signature': cds}


def audit(data):
    require(u32(data, 0, '>') == 0xcafebabe and u32(data, 4, '>') == 2, 'expected exactly two fat slices')
    results = []
    for i, arch in enumerate(('arm64', 'arm64e')):
        cpu, subtype, offset, size, align = struct.unpack_from('>5I', data, 8 + i * 20)
        require(offset + size <= len(data), 'fat slice bounds')
        results.append(audit_slice(data[offset:offset+size], arch))
    return results


if __name__ == '__main__':
    data = pathlib.Path(sys.argv[1]).read_bytes()
    result = audit(data)
    # Negative check: alter an ignored dylib timestamp, which page hashing must reject.
    broken = bytearray(data)
    base = u32(data, 16, '>')
    p = base + 32
    while u32(data, p) != 0xd:
        p += u32(data, p + 4)
    broken[p + 12] ^= 1
    try:
        audit(bytes(broken))
    except ValueError as e:
        require(str(e) == 'CodeDirectory page hash mismatch', 'negative test failed for wrong reason')
    else:
        raise ValueError('tampered signature unexpectedly accepted')
    print(json.dumps({'sha256': hashlib.sha256(data).hexdigest(), 'slices': result,
                      'negative_test': 'modified dylib timestamp rejected by page hash'}, indent=2))
