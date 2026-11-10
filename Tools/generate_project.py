#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project using only Python's standard library."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = []
def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key, body):
    value = ident(key)
    objects.append(f'{value} = {{ {body} }};')
    return value
def listing(items):
    return '(' + ', '.join(items) + (',' if items else '') + ')'
def quoted(value):
    return '"' + value + '"'

files = {}
for directory in ['Shared', 'SharedUI', 'iOS', 'macOS']:
    for path in sorted((ROOT / directory).iterdir()):
        if path.suffix not in ['.swift', '.entitlements']:
            continue
        name = str(path.relative_to(ROOT))
        kind = 'sourcecode.swift' if path.suffix == '.swift' else 'text.plist.entitlements'
        files[name] = add(name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(name)}; sourceTree = SOURCE_ROOT;')
readme = add('readme', 'isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = README.md; sourceTree = SOURCE_ROOT;')
product_ids = []
targets = []
for platform, target in [('iOS', 'CaseSensitivityTester-iOS'), ('macOS', 'CaseSensitivityTester-macOS')]:
    product = add(target + 'product', f'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {quoted(target + ".app")}; sourceTree = BUILT_PRODUCTS_DIR;')
    product_ids.append(product)
    build_files = []
    for path, reference in files.items():
        if path.endswith('.swift') and path.split('/')[0] in ['Shared', 'SharedUI', platform]:
            build_files.append(add(target + path, f'isa = PBXBuildFile; fileRef = {reference};'))
    sources = add(target + 'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing(build_files)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add(target + 'frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resources = add(target + 'resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    configs = []
    for mode in ['Debug', 'Release']:
        settings = {
            'PRODUCT_NAME': quoted(target), 'PRODUCT_BUNDLE_IDENTIFIER': 'io.github.watr.CaseSensitivityTester.' + platform,
            'SWIFT_VERSION': '5.0', 'GENERATE_INFOPLIST_FILE': 'YES', 'MARKETING_VERSION': '1.0',
            'CURRENT_PROJECT_VERSION': '1', 'CODE_SIGN_STYLE': 'Automatic',
            'INFOPLIST_KEY_CFBundleDisplayName': quoted('Case Sensitivity Tester'),
            'SWIFT_EMIT_LOC_STRINGS': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
            'SWIFT_OPTIMIZATION_LEVEL': quoted('-Onone' if mode == 'Debug' else '-O'),
        }
        if platform == 'iOS':
            settings.update(SDKROOT='iphoneos', SUPPORTED_PLATFORMS=quoted('iphoneos iphonesimulator'),
                            TARGETED_DEVICE_FAMILY=quoted('1,2'), IPHONEOS_DEPLOYMENT_TARGET='16.0',
                            SUPPORTS_MACCATALYST='NO', INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',
                            INFOPLIST_KEY_UILaunchScreen_Generation='YES',
                            INFOPLIST_KEY_UISupportedInterfaceOrientations=quoted('UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'),
                            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad=quoted('UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'))
        else:
            settings.update(SDKROOT='macosx', SUPPORTED_PLATFORMS='macosx', MACOSX_DEPLOYMENT_TARGET='13.0',
                            CODE_SIGN_ENTITLEMENTS='macOS/CaseSensitivityTester.entitlements', ENABLE_APP_SANDBOX='YES',
                            INFOPLIST_KEY_LSApplicationCategoryType=quoted('public.app-category.developer-tools'),
                            LD_RUNPATH_SEARCH_PATHS=quoted('$(inherited) @executable_path/../Frameworks'))
        text = ' '.join(f'{k} = {v};' for k, v in settings.items())
        configs.append(add(target + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {mode};'))
    config_list = add(target + 'configs', f'isa = XCConfigurationList; buildConfigurations = {listing(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target_id = add(target, f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {listing([sources, frameworks, resources])}; buildRules = (); dependencies = (); name = {quoted(target)}; productName = {quoted(target)}; productReference = {product}; productType = "com.apple.product-type.application";')
    targets.append(target_id)
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2720" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:CaseSensitivityTester.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:CaseSensitivityTester.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{target}.app" BlueprintName="{target}" ReferencedContainer="container:CaseSensitivityTester.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (ROOT / 'CaseSensitivityTester.xcodeproj/xcshareddata/xcschemes' / (target + '.xcscheme')).write_text(scheme)
products = add('products', f'isa = PBXGroup; children = {listing(product_ids)}; name = Products; sourceTree = "<group>";')
groups = []
for directory in ['Shared', 'SharedUI', 'iOS', 'macOS']:
    refs = [ref for path, ref in files.items() if path.startswith(directory + '/')]
    groups.append(add('group' + directory, f'isa = PBXGroup; children = {listing(refs)}; name = {directory}; sourceTree = "<group>";'))
main = add('main', f'isa = PBXGroup; children = {listing([readme] + groups + [products])}; sourceTree = "<group>";')
configs = []
for mode in ['Debug', 'Release']:
    settings = 'CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_WARN_INHIBIT_ALL_WARNINGS = NO; SWIFT_STRICT_CONCURRENCY = complete;'
    if mode == 'Debug':
        settings += ' SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ENABLE_TESTABILITY = YES; ONLY_ACTIVE_ARCH = YES;'
    configs.append(add('project' + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};'))
config_list = add('projectConfigs', f'isa = XCConfigurationList; buildConfigurations = {listing(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project = add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2720; }}; buildConfigurationList = {config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja, en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {listing(targets)};')
(ROOT / 'CaseSensitivityTester.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n' + '\n'.join(objects) + f'\n}};\nrootObject = {project};\n}}\n')
