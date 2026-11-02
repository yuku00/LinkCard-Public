"""Build9: explicit noncontainer profile, without HOME rebinding or extra storage rights."""
BUNDLE_ID = 'org.example.WebClipManager'
BUILD = '23'
ALLOWED_ENTITLEMENTS = {
    'platform-application': True,
    'application-identifier': BUNDLE_ID,
    'com.apple.private.security.container-required': False,
    'com.apple.private.security.no-container': True,
    'com.apple.private.security.no-sandbox': True,
    'com.apple.private.security.storage.AppDataContainers': True,
    'com.apple.private.security.storage.Notes': True,
    'com.apple.private.security.storage.Safari': True,
}

def validate_entitlements(value):
    assert isinstance(value, dict) and set(value) == set(ALLOWED_ENTITLEMENTS), 'Unreviewed/missing entitlement'
    for key, expected in ALLOWED_ENTITLEMENTS.items():
        assert type(value[key]) is type(expected) and value[key] == expected, 'Wrong entitlement value: ' + key


def decode_der(data):
    """Strict decoder for this profile's SET of SEQUENCE(UTF8 key, bool/string)."""
    def item(offset, limit):
        assert offset + 2 <= limit
        tag, length = data[offset:offset + 2]
        offset += 2
        if length & 128:
            count = length & 127
            assert 0 < count <= 4 and offset + count <= limit
            length = int.from_bytes(data[offset:offset + count], 'big')
            offset += count
        end = offset + length
        assert end <= limit
        if tag in (0x30, 0x31):
            value = []
            while offset < end:
                child, offset = item(offset, end)
                value.append(child)
            if tag == 0x31:
                result = {}
                for pair in value:
                    assert isinstance(pair, list) and len(pair) == 2 and isinstance(pair[0], str)
                    assert pair[0] not in result
                    result[pair[0]] = pair[1]
                value = result
        elif tag == 0x0c:
            value = data[offset:end].decode('utf-8')
        elif tag == 1:
            # ldid 2.1.5 emits 0x01 for true; also accept canonical DER 0xff.
            # Keep the length and explicit value allowlist (not arbitrary nonzero).
            assert length == 1 and data[offset] in (0, 1, 255)
            value = data[offset] != 0
        else:
            raise AssertionError('Unexpected DER tag')
        return value, end
    value, end = item(0, len(data))
    assert end == len(data) and isinstance(value, dict)
    return value


def self_test():
    validate_entitlements(ALLOWED_ENTITLEMENTS)
    for bad in [dict(ALLOWED_ENTITLEMENTS, **{'get-task-allow': True}),
                dict(ALLOWED_ENTITLEMENTS, **{'application-identifier': 'com.trollscript.dom'}),
                dict(ALLOWED_ENTITLEMENTS, **{'com.apple.private.security.container-required': BUNDLE_ID}),
                {'com.apple.private.security.no-sandbox': True}]:
        try:
            validate_entitlements(bad)
        except AssertionError:
            pass
        else:
            raise AssertionError('Unsafe profile accepted')
    assert decode_der(bytes.fromhex('310830060c01610101ff')) == {'a': True}
    assert decode_der(bytes.fromhex('310830060c0161010101')) == {'a': True}
    for bad in [b'', bytes.fromhex('310830060c01610101ff00'), bytes.fromhex('310830060c0161010102')]:
        try:
            decode_der(bad)
        except AssertionError:
            pass
        else:
            raise AssertionError('Malformed DER accepted')
