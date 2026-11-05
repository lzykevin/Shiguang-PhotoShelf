#!/usr/bin/env python3
"""Generate a Xcode app + native Swift static library project."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()

def obj(label, body):
    key = uid(label)
    objects[key] = body
    return key

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

def listing(values):
    return "(" + ", ".join(values) + ",)" if values else "()"

def settings(values):
    return "{ " + " ".join(f"{k} = {q(v)};" for k, v in values.items()) + " }"

def configs(label, values):
    ids = []
    for name in ["Debug", "Release"]:
        config = dict(values)
        config["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
        config["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG" if name == "Debug" else ""
        ids.append(obj(label + name, f"isa = XCBuildConfiguration; buildSettings = {settings(config)}; name = {name};"))
    return obj(label + "configs", f"isa = XCConfigurationList; buildConfigurations = {listing(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

project_id, app_id, core_id = map(uid, ["project", "app", "core"])
product_app = obj("productApp", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = PhotoShelf.app; sourceTree = BUILT_PRODUCTS_DIR;')
product_core = obj("productCore", 'isa = PBXFileReference; explicitFileType = archive.ar; path = libPhotoLibraryCore.a; sourceTree = BUILT_PRODUCTS_DIR;')
groups = []
phases = {}
for module in ["PhotoLibraryCore", "PhotoShelf"]:
    refs, builds = [], []
    for path in sorted((ROOT / "Sources" / module).glob("*.swift")):
        relative = path.relative_to(ROOT)
        ref = obj(str(relative), f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
        refs.append(ref)
        builds.append(obj("build" + str(relative), f"isa = PBXBuildFile; fileRef = {ref};"))
    groups.append(obj(module + "group", f"isa = PBXGroup; children = {listing(refs)}; name = {module}; sourceTree = \"<group>\";"))
    phases[module] = obj(module + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing(builds)}; runOnlyForDeploymentPostprocessing = 0;")

resource_refs, resource_builds = [], []
for name in ["Info.plist", "PhotoShelf.entitlements", "AppIcon.icns"]:
    kind = "image.icns" if name.endswith("icns") else "text.plist.xml"
    ref = obj(name, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {q('Resources/' + name)}; sourceTree = SOURCE_ROOT;")
    resource_refs.append(ref)
    if name.endswith("icns"):
        resource_builds.append(obj("iconbuild", f"isa = PBXBuildFile; fileRef = {ref};"))
sample_ref = obj("samples", 'isa = PBXFileReference; lastKnownFileType = folder; path = "Sources/PhotoShelf/Resources/Samples"; sourceTree = SOURCE_ROOT;')
resource_refs.append(sample_ref)
resource_builds.append(obj("samplesBuild", f'isa = PBXBuildFile; fileRef = {sample_ref};'))
groups.append(obj("resourcesgroup", f"isa = PBXGroup; children = {listing(resource_refs)}; name = Resources; sourceTree = \"<group>\";"))
products = obj("products", f"isa = PBXGroup; children = {listing([product_app, product_core])}; name = Products; sourceTree = \"<group>\";")
main = obj("main", f"isa = PBXGroup; children = {listing(groups + [products])}; sourceTree = \"<group>\";")
proxy = obj("proxy", f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {core_id}; remoteInfo = PhotoLibraryCore;")
dependency = obj("dependency", f"isa = PBXTargetDependency; target = {core_id}; targetProxy = {proxy};")
link = obj("link", f"isa = PBXBuildFile; fileRef = {product_core};")
sparkle_package = obj("sparklePackage", 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = exactVersion; version = 2.10.1; };')
sparkle_product = obj("sparkleProduct", f'isa = XCSwiftPackageProductDependency; package = {sparkle_package}; productName = Sparkle;')
sparkle_link = obj("sparkleLink", f'isa = PBXBuildFile; productRef = {sparkle_product};')
frameworks = obj("frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {listing([link, sparkle_link])}; runOnlyForDeploymentPostprocessing = 0;")
resources = obj("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {listing(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;")
common = {"MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0", "SDKROOT": "macosx", "CLANG_ENABLE_MODULES": "YES", "SWIFT_STRICT_CONCURRENCY": "targeted"}
core_settings = dict(common, PRODUCT_NAME="PhotoLibraryCore", PRODUCT_MODULE_NAME="PhotoLibraryCore", DEFINES_MODULE="YES", SKIP_INSTALL="YES", MACH_O_TYPE="staticlib")
app_settings = dict(common, PRODUCT_NAME="PhotoShelf", PRODUCT_BUNDLE_IDENTIFIER="com.photoshelf.local", INFOPLIST_FILE="Resources/Info.plist", CODE_SIGN_ENTITLEMENTS="Resources/PhotoShelf.entitlements", CODE_SIGN_IDENTITY="-", CODE_SIGN_STYLE="Manual", ENABLE_APP_SANDBOX="YES", ENABLE_HARDENED_RUNTIME="YES", SWIFT_INCLUDE_PATHS="$(BUILT_PRODUCTS_DIR)", LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/../Frameworks")
objects[core_id] = f"isa = PBXNativeTarget; buildConfigurationList = {configs('core', core_settings)}; buildPhases = {listing([phases['PhotoLibraryCore']])}; buildRules = (); dependencies = (); name = PhotoLibraryCore; productName = PhotoLibraryCore; productReference = {product_core}; productType = \"com.apple.product-type.library.static\";"
objects[app_id] = f"isa = PBXNativeTarget; buildConfigurationList = {configs('app', app_settings)}; buildPhases = {listing([phases['PhotoShelf'], frameworks, resources])}; buildRules = (); dependencies = {listing([dependency])}; packageProductDependencies = {listing([sparkle_product])}; name = PhotoShelf; productName = PhotoShelf; productReference = {product_app}; productType = \"com.apple.product-type.application\";"
objects[project_id] = f"isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {configs('project', common)}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = \"\"; projectRoot = \"\"; packageReferences = {listing([sparkle_package])}; targets = {listing([app_id, core_id])};"
project = ROOT / "PhotoShelf.xcodeproj"
project.mkdir(exist_ok=True)
content = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
content += "\n".join(f"{key} = {{ {body} }};" for key, body in sorted(objects.items()))
content += f"\n}}; rootObject = {project_id}; }}\n"
(project / "project.pbxproj").write_text(content)
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="PhotoShelf.app" BlueprintName="PhotoShelf" ReferencedContainer="container:PhotoShelf.xcodeproj"/>'
(scheme_dir / "PhotoShelf.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(project)
