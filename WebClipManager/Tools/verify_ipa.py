"""Inspect a device IPA without executing it. Not an iOS launch/CoreTrust test."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile


def inspect(path, require_icon=True, helper=False):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert all(n.startswith('Payload/') and '..' not in n.split('/') for n in names)
        prefix = 'Payload/WebClipManager.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        assert info['CFBundleIdentifier'] == 'org.example.WebClipManager'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['MinimumOSVersion'] == '16.0'
        executable = prefix + ('WebClipReadHelper' if helper else info['CFBundleExecutable'])
        mode = archive.getinfo(executable).external_attr >> 16
        assert mode & 0o111 and not mode & 0o6000, 'Executable must not be setuid/setgid'
        if helper: assert mode & 0o777 == 0o755
        binary = archive.read(executable)
        magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from('<8I', binary)
        assert (magic, cpu, kind) == (0xfeedfacf, 0x100000c, 2), 'Expected arm64 device executable'
        offset = 32
        libraries, rpaths, platform, signature = [], [], None, None
        for _ in range(count):
            cmd, length = struct.unpack_from('<II', binary, offset)
            assert length >= 8 and offset + length <= 32 + size
            if cmd in (0xc, 0x80000018, 0x8000001f):
                start = struct.unpack_from('<I', binary, offset + 8)[0]
                name = binary[offset + start:offset + length].split(b'\0')[0].decode()
                libraries.append({'name': name, 'weak': cmd == 0x80000018})
                if name.startswith('@rpath/'):
                    assert prefix + 'Frameworks/' + name[7:] in names, 'Missing embedded dependency: ' + name
                else:
                    assert name.startswith(('/usr/lib/', '/System/Library/')), name
            elif cmd == 0x8000001c:
                start = struct.unpack_from('<I', binary, offset + 8)[0]
                rpaths.append(binary[offset + start:offset + length].split(b'\0')[0].decode())
            elif cmd == 0x32:
                platform, minimum, sdk = struct.unpack_from('<III', binary, offset + 8)
                assert platform == 2 and minimum == 0x100000, 'Wrong platform/minimum OS'
            elif cmd == 0x1d:
                signature = struct.unpack_from('<II', binary, offset + 8)
            offset += length
        assert platform == 2 and signature
        start, length = signature
        sig = binary[start:start + length]
        magic, total, count = struct.unpack_from('>III', sig)
        assert magic == 0xfade0cc0 and total <= len(sig)
        blobs = {}
        for i in range(count):
            slot, pos = struct.unpack_from('>II', sig, 12 + 8 * i)
            magic, length = struct.unpack_from('>II', sig, pos)
            assert pos + length <= total
            blobs[slot] = sig[pos:pos + length]
        entitlements = plistlib.loads(blobs[5][8:])
        from entitlement_policy import validate_entitlements, decode_der, BUILD
        assert info['CFBundleVersion'] == BUILD
        assert info.get('UIFileSharingEnabled') is False
        assert info.get('LSSupportsOpeningDocumentsInPlace') is False
        if helper:
            def validate_entitlements(value):
                expected = plistlib.load(open(__file__.replace("Tools/verify_ipa.py", "Config/Helper.entitlements"), "rb"))
                assert value == expected and all(type(value[k]) is type(v) for k,v in expected.items())
        validate_entitlements(entitlements)
        assert struct.unpack_from('>I', blobs[7])[0] == 0xfade7172
        der_entitlements = decode_der(blobs[7][8:])
        validate_entitlements(der_entitlements)
        assert der_entitlements == entitlements, 'XML/DER mismatch'
        directories = []
        for slot, cd in blobs.items():
            if slot != 0 and not 0x1000 <= slot < 0x1005:
                continue
            magic, length, version, flags, hash_offset, ident_offset, special, pages, limit = struct.unpack_from('>9I', cd)
            hash_size, hash_type, platform_byte, page_power = struct.unpack_from('4B', cd, 36)
            assert magic == 0xfade0c02 and hash_type in (1, 2, 3)
            hasher = hashlib.sha1 if hash_type == 1 else hashlib.sha256
            page_size = 1 << page_power
            assert limit == start and pages == (limit + page_size - 1) // page_size
            for page in range(pages):
                expected = cd[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
                assert hasher(binary[page * page_size:min((page + 1) * page_size, limit)]).digest()[:hash_size] == expected, 'Code page hash mismatch'
            for special_slot in (5, 7):
                if special_slot in blobs:
                    assert special >= special_slot
                    expected = cd[hash_offset - special_slot * hash_size:hash_offset - (special_slot - 1) * hash_size]
                    assert hasher(blobs[special_slot]).digest()[:hash_size] == expected, 'Entitlement digest mismatch'
            directories.append({'version': hex(version), 'flags': hex(flags), 'hashType': hash_type, 'pagesVerified': pages})
        assert directories
        icons = {k: info.get(k) for k in ('CFBundleIcons', 'CFBundleIcons~ipad')}
        if require_icon:
            assert prefix + 'Assets.car' in names, 'Missing compiled asset catalog'
            for key, value in icons.items():
                assert value and value['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon', 'Missing icon declaration: ' + key
                files = value['CFBundlePrimaryIcon']['CFBundleIconFiles']
                assert files and any(n.startswith(prefix + f) and n.endswith('.png') for f in files for n in names)
        result = {'sha256': hashlib.sha256(open(path, 'rb').read()).hexdigest(), 'info': info,
                  'codeDirectories': directories, 'entitlements': entitlements, 'derEntitlements': der_entitlements, 'signatureSlots': sorted(blobs),
                  'platform': platform, 'minimumOS': '16.0', 'sdk': '%d.%d.%d' % (sdk >> 16, sdk >> 8 & 255, sdk & 255),
                  'libraries': libraries, 'rpaths': rpaths, 'icons': icons,
                  'limitations': 'Static validation only; no device launch, dyld symbol availability, or installed CoreTrust verification.'}
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return result


if __name__ == '__main__':
    inspect(sys.argv[1], require_icon='--allow-missing-icon' not in sys.argv[2:])
    inspect(sys.argv[1], require_icon=False, helper=True)
