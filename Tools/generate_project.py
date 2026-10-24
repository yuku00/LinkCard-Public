# SPDX-License-Identifier: GPL-3.0-or-later
"""Deterministic Xcode project generation; standard library only."""
from pathlib import Path
import hashlib, json, plistlib, zlib, struct, shutil
R = Path(__file__).resolve().parents[1]
P = R/'LinkCard.xcodeproj'
P.mkdir(exist_ok=True)
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(key, isa, **values):
    objects[ident(key)] = dict(isa=isa, **values)
    return ident(key)
def ref(name): return ident(name)
def encode(v, depth=0):
    if isinstance(v, dict):
        return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+encode(x,depth+1)+';\n' for k,x in v.items())+'\t'*depth+'}'
    if isinstance(v, list): return '('+', '.join(encode(x,depth+1) for x in v)+')'
    return json.dumps(str(v), ensure_ascii=False)
source_names = ['ContentView.swift','FrameCodec.swift','CardRenderer.swift','NFCService.swift',
                'PCRProtocol.swift','PCRBluetooth.swift','LocalCardLibrary.swift','LocalDeviceViews.swift','MistDesign.swift',
                'BLEProfiles.swift','BLEPreferencesView.swift','FusionGeometry.swift','FusionShell.swift','FusionProfile.swift','FusionMotion.swift','DrawerRenderOwner.swift']
files = []
for name in source_names:
    f = obj(name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=name,sourceTree='<group>')
    files.append(f)
    obj('build '+name,'PBXBuildFile',fileRef=f)
for name, typ in [('Info.plist','text.plist.xml'),('LinkCard.entitlements','text.plist.entitlements'),('Assets.xcassets','folder.assetcatalog')]:
    files.append(obj(name,'PBXFileReference',lastKnownFileType=typ,path=name,sourceTree='<group>'))
obj('build assets','PBXBuildFile',fileRef=ref('Assets.xcassets'))
obj('app group','PBXGroup',children=files,path='LinkCard',sourceTree='<group>')
obj('test file','PBXFileReference',lastKnownFileType='sourcecode.swift',path='FrameCodecTests.swift',sourceTree='<group>')
obj('test build','PBXBuildFile',fileRef=ref('test file'))
obj('tests group','PBXGroup',children=[ref('test file')],path='LinkCardTests',sourceTree='<group>')
obj('app product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='LinkCard.app',sourceTree='BUILT_PRODUCTS_DIR')
obj('test product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='LinkCardTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
obj('ui file','PBXFileReference',lastKnownFileType='sourcecode.swift',path='LinkCardFullAppTouchTests.swift',sourceTree='<group>')
obj('ui build','PBXBuildFile',fileRef=ref('ui file'))
obj('ui group','PBXGroup',children=[ref('ui file')],path='LinkCardUITests',sourceTree='<group>')
obj('ui product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='LinkCardUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
obj('products','PBXGroup',children=[ref('app product'),ref('test product'),ref('ui product')],name='Products',sourceTree='<group>')
obj('root group','PBXGroup',children=[ref('app group'),ref('tests group'),ref('ui group'),ref('products')],sourceTree='<group>')
for target, sources, resources in [('app',[ref('build '+n) for n in source_names],[ref('build assets')]),('test',[ref('test build')],[]),('ui',[ref('ui build')],[])]:
    for phase, isa, entries in [('sources','PBXSourcesBuildPhase',sources),('resources','PBXResourcesBuildPhase',resources),('frameworks','PBXFrameworksBuildPhase',[])]:
        obj(target+' '+phase,isa,buildActionMask='2147483647',files=entries,runOnlyForDeploymentPostprocessing='0')
obj('proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType='1',remoteGlobalIDString=ref('app target'),remoteInfo='LinkCard')
obj('dependency','PBXTargetDependency',target=ref('app target'),targetProxy=ref('proxy'))
for target, product, typ in [('app','LinkCard','com.apple.product-type.application'),('test','LinkCardTests','com.apple.product-type.bundle.unit-test'),('ui','LinkCardUITests','com.apple.product-type.bundle.ui-testing')]:
    obj(target+' target','PBXNativeTarget',buildConfigurationList=ref(target+' configs'),buildPhases=[ref(target+' '+p) for p in ['sources','frameworks','resources']],buildRules=[],dependencies=[ref('dependency')] if target!='app' else [],name=product,productName=product,productReference=ref(target+' product'),productType=typ)
for scope in ['project','app','test','ui']:
    configs=[]
    for mode in ['Debug','Release']:
        if scope=='project':
            settings=dict(IPHONEOS_DEPLOYMENT_TARGET='16.0',SDKROOT='iphoneos',SWIFT_VERSION='5.0',CLANG_ENABLE_MODULES='YES',SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym',ENABLE_TESTABILITY='YES' if mode=='Debug' else 'NO',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if mode=='Debug' else '')
        elif scope=='app':
            settings=dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='org.example.LinkCard',INFOPLIST_FILE='LinkCard/Info.plist',GENERATE_INFOPLIST_FILE='NO',CODE_SIGN_ENTITLEMENTS='LinkCard/LinkCard.entitlements',CODE_SIGN_STYLE='Automatic',TARGETED_DEVICE_FAMILY='1,2',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',CURRENT_PROJECT_VERSION='24',MARKETING_VERSION='0.8.5',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'],SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO')
        elif scope=='ui':
            settings=dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='org.example.LinkCardUITests',GENERATE_INFOPLIST_FILE='YES',CODE_SIGN_STYLE='Automatic',TARGETED_DEVICE_FAMILY='1,2',TEST_TARGET_NAME='LinkCard',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks'])
        else:
            settings=dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='org.example.LinkCardTests',GENERATE_INFOPLIST_FILE='YES',CODE_SIGN_STYLE='Automatic',TARGETED_DEVICE_FAMILY='1,2',TEST_HOST='$(BUILT_PRODUCTS_DIR)/LinkCard.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LinkCard',BUNDLE_LOADER='$(TEST_HOST)',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks'])
        if scope in ('test','ui'):
            settings.update(CURRENT_PROJECT_VERSION='24',MARKETING_VERSION='0.8.5')
        configs.append(obj(scope+' '+mode,'XCBuildConfiguration',buildSettings=settings,name=mode))
    obj(scope+' configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
obj('project','PBXProject',attributes={'LastUpgradeCheck':'1500','TargetAttributes':{ref('app target'):{'SystemCapabilities':{'com.apple.NearFieldCommunicationTagReading':{'enabled':'1'}}},ref('test target'):{'TestTargetID':ref('app target')},ref('ui target'):{'TestTargetID':ref('app target')}}},buildConfigurationList=ref('project configs'),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings='0',knownRegions=['zh-Hans','en','Base'],mainGroup=ref('root group'),productRefGroup=ref('products'),projectDirPath='',projectRoot='',targets=[ref('app target'),ref('test target'),ref('ui target')])
project=dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=ref('project'))
(P/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(project)+'\n')
info=dict(CFBundleDisplayName='Link-Card',CFBundleName='$(PRODUCT_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundlePackageType='APPL',CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)',LSRequiresIPhoneOS=True,UILaunchScreen={},NSBluetoothAlwaysUsageDescription='授权后仅在前台发现自有蓝牙设备；首次连接须确认，记住后可自动连接。关闭提示不撤销自动连接授权，不自动寻卡、写卡或发送业务命令。',NFCReaderUsageDescription='只读识别您的 ST25DV Link-Card，并在确认后通过临时邮箱发送单色图像。',UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],**{'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationPortraitUpsideDown']})
for name,value in [('Info.plist',info),('LinkCard.entitlements',{'com.apple.developer.nfc.readersession.formats':['TAG']})]:
    (R/'LinkCard'/name).write_bytes(plistlib.dumps(value,sort_keys=False))
# Asset catalog: generate an opaque original geometric icon, no external asset.
assets=R/'LinkCard/Assets.xcassets'; icons=assets/'AppIcon.appiconset'; icons.mkdir(parents=True,exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}}))
def png(size):
    rows=[]
    for y in range(size):
        row=bytearray([0])
        for x in range(size):
            u,v=x/size,y/size
            color=(25,87,77)
            if .23<u<.77 and .15<v<.85: color=(244,245,235)
            if .33<u<.67 and (.29<v<.36 or .46<v<.53 or .63<v<.70): color=(25,87,77)
            row.extend(color)
        rows.append(bytes(row))
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b'')
(icons/'AppIcon.png').write_bytes(png(1024))
(icons/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'version':1,'author':'xcode'}}))
print('Generated',P)
