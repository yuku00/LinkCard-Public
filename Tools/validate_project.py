# SPDX-License-Identifier: GPL-3.0-or-later
"""Parse generated OpenStep plist and validate references, files and settings.
This is structural validation, NOT Swift parsing, linking or Xcode validation.
"""
from pathlib import Path
import re, json, plistlib, xml.etree.ElementTree as ET
R = Path(__file__).resolve().parents[1]
text=(R/'LinkCard.xcodeproj/project.pbxproj').read_text()
text=re.sub(r'//[^\n]*','',text)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text)
i=0
def take():
    global i
    result=tokens[i]; i+=1; return result
def expect(v):
    assert take()==v, ('expected',v)
def value():
    t=take()
    if t=='{':
        out={}
        while tokens[i]!='}':
            key=value(); expect('='); out[key]=value(); expect(';')
        expect('}'); return out
    if t=='(':
        out=[]
        while tokens[i]!=')':
            out.append(value())
            if tokens[i]==',': take()
        expect(')'); return out
    return json.loads(t) if t.startswith('"') else t
p=value(); assert i==len(tokens)
objects=p['objects']; assert p['rootObject'] in objects
assert len(objects)==len(set(objects))
ref_keys={'fileRef','mainGroup','productRefGroup','productReference','buildConfigurationList','target','targetProxy','containerPortal','remoteGlobalIDString','TestTargetID'}
array_keys={'children','targets','buildConfigurations','buildPhases','dependencies','files'}
for key,o in objects.items():
    assert re.fullmatch('[0-9A-F]{24}',key)
    assert 'isa' in o
    for field,v in o.items():
        if field in ref_keys: assert v in objects,(key,field,v)
        if field in array_keys:
            for x in v: assert x in objects,(key,field,x)
    if o['isa']=='PBXBuildFile': assert objects[o['fileRef']]['isa']=='PBXFileReference'
    if o['isa']=='PBXFileReference' and o.get('sourceTree')=='<group>':
        folder={'FrameCodecTests.swift':'LinkCardTests','LinkCardFullAppTouchTests.swift':'LinkCardUITests'}.get(o['path'],'LinkCard')
        assert (R/folder/o['path']).exists(),o['path']
app=next(o for o in objects.values() if o['isa']=='PBXNativeTarget' and o['name']=='LinkCard')
assert app['productType']=='com.apple.product-type.application'
source_phase=next(objects[x] for x in app['buildPhases'] if objects[x]['isa']=='PBXSourcesBuildPhase')
compiled_sources = {objects[objects[x]['fileRef']]['path'] for x in source_phase['files']}
expected_sources = {file.name for file in (R/'LinkCard').glob('*.swift')}
assert compiled_sources == expected_sources, ('source membership mismatch', compiled_sources ^ expected_sources)
assert len(source_phase['files']) == len(compiled_sources), 'duplicate source build entries'
for name, product_type, source in [('LinkCardTests','unit-test','FrameCodecTests.swift'), ('LinkCardUITests','ui-testing','LinkCardFullAppTouchTests.swift')]:
    target=next(o for o in objects.values() if o['isa']=='PBXNativeTarget' and o['name']==name)
    assert target['productType']=='com.apple.product-type.bundle.'+product_type
    phase=next(objects[x] for x in target['buildPhases'] if objects[x]['isa']=='PBXSourcesBuildPhase')
    assert [objects[objects[x]['fileRef']]['path'] for x in phase['files']]==[source]
    for config in objects[target['buildConfigurationList']]['buildConfigurations']:
        settings=objects[config]['buildSettings']
        assert settings['MARKETING_VERSION']=='0.9.1' and settings['CURRENT_PROJECT_VERSION']=='27'
        if product_type=='ui-testing':
            assert settings['TEST_TARGET_NAME']=='LinkCard' and 'TEST_HOST' not in settings
with (R/'LinkCard/Info.plist').open('rb') as f: info=plistlib.load(f)
with (R/'LinkCard/LinkCard.entitlements').open('rb') as f: ent=plistlib.load(f)
assert info['NFCReaderUsageDescription']
assert ent=={'com.apple.developer.nfc.readersession.formats':['TAG']}
for f in (R/'LinkCard.xcodeproj/xcshareddata/xcschemes').glob('*.xcscheme'):
    tree=ET.parse(f)
    for ref in tree.findall('.//BuildableReference'): assert ref.attrib['BlueprintIdentifier'] in objects
print(f'PASS: OpenStep parsed; {len(objects)} objects; all references and source files resolved; plists/scheme valid')
print('NOT a Swift compile or a CoreNFC/hardware test.')
