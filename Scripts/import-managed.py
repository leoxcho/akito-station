#!/usr/bin/env python3
"""Import a user-supplied executable for local use. No download or game boot.
Retains bundle licenses; records binary provenance. Not a redistribution/source-build tool.
"""
import argparse,hashlib,json,pathlib,plistlib,shutil,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--engine',required=True,choices=['ppsspp_sdl','duckstation','rpcs3','armsx2','pcsx2','vita3k','eden','ryujinx','shadps4','lime3ds','cemu','xemu','xenia','azahar','dolphin_app','flycast']);p.add_argument('--register-external',action='store_true');p.add_argument('--app',required=True,type=pathlib.Path);p.add_argument('--root',required=True,type=pathlib.Path);p.add_argument('--platform');p.add_argument('--no-activate',action='store_true');p.add_argument('--require-signature',action='store_true');p.add_argument('--upstream');p.add_argument('--release');p.add_argument('--result-file',type=pathlib.Path);a=p.parse_args()
if a.root.resolve()==a.app.resolve() or a.root.resolve() in a.app.resolve().parents or a.app.resolve() in a.root.resolve().parents:raise ValueError('Application and runtime storage must not overlap')
info=plistlib.loads((a.app/'Contents/Info.plist').read_bytes());relative=pathlib.Path(a.app.name)/'Contents/MacOS'/info['CFBundleExecutable'];exe=a.app/'Contents/MacOS'/info['CFBundleExecutable']
if not isinstance(info.get('CFBundleExecutable'),str) or pathlib.Path(info['CFBundleExecutable']).name!=info['CFBundleExecutable']:raise ValueError('Invalid bundle executable')
if a.app.resolve() not in exe.resolve().parents:raise ValueError('Executable escapes application')
platforms={'ppsspp_sdl':['psp'],'duckstation':['ps1'],'rpcs3':['ps3'],'armsx2':['ps2'],'pcsx2':['ps2'],'eden':['switchConsole'],'vita3k':['psvita'],'ryujinx':['switchConsole'],'shadps4':['ps4'],'lime3ds':['n3ds'],'cemu':['wiiu'],'xemu':['xbox'],'xenia':['xbox360'],'azahar':['n3ds'],'dolphin_app':['gc','wii'],'flycast':['dreamcast']}
if a.platform and a.platform not in platforms[a.engine]:raise ValueError('Emulator does not support the selected console')
is_pcsx2=info.get('CFBundleIdentifier','').lower()=='net.pcsx2.pcsx2'
if (a.engine=='pcsx2') != is_pcsx2:raise ValueError('PCSX2 must use the PCSX2 adapter and belongs to PlayStation 2')
sha=lambda f:hashlib.file_digest(f.open('rb'),'sha256').hexdigest() if hasattr(hashlib,'file_digest') else hashlib.sha256(f.read_bytes()).hexdigest()
hash=sha(exe);archs=subprocess.check_output(['lipo','-archs',exe],text=True).split();assert 'arm64' in archs or archs==['x86_64']
# Check the supplied bundle as-is. Never alter the original or strip its entitlements.
source_signature=subprocess.run(['codesign','--verify','--deep',str(a.app)],capture_output=True).returncode==0

if a.require_signature and not source_signature:raise ValueError('Downloaded app signature is invalid; runtime was not installed')
version=hash[:12]+'-local1';parent=a.root/a.engine;parent.mkdir(parents=True,exist_ok=True);dest=parent/version
upstream={'ppsspp_sdl':'hrydgard/ppsspp','duckstation':'stenzek/duckstation','rpcs3':'RPCS3/rpcs3','armsx2':'ARMSX2/ARMSX2','pcsx2':'PCSX2/pcsx2','eden':'eden-emulator/Releases','vita3k':'Vita3K/Vita3K','ryujinx':'ryujinx-mirror/ryujinx','shadps4':'shadps4-emu/shadPS4','lime3ds':'Lime3DS/Lime3DS','cemu':'cemu-project/Cemu','xemu':'xemu-project/xemu','xenia':'xenia-project/xenia','azahar':'azahar-emu/azahar','dolphin_app':'dolphin-emu/dolphin','flycast':'flyinghead/flycast'}[a.engine]
if a.register_external:
 if not source_signature:raise ValueError('External app signature is invalid; original was not changed')
 app=a.app.resolve();binary=exe.resolve()
 if app not in binary.parents:raise ValueError('Executable escapes application')
 version=hash[:12]+'-external';dest=parent/version;dest.mkdir(exist_ok=True)
 manifest=dict(id=a.engine,platforms=platforms[a.engine],version=version,upstream=a.upstream or ('https://git.eden-emu.dev/eden-emu/eden' if a.engine=='eden' else 'https://github.com/'+upstream),revision=info.get('CFBundleShortVersionString','local'),integrationRevision='1',architecture='arm64' if 'arm64' in archs else 'x86_64',library=str(pathlib.Path('Contents/MacOS')/info['CFBundleExecutable']),sha256=hash,capabilities=['nativeWindow','externalRuntime','gameUntested'],channel='external',validated=True,license='See installed bundle notices',externalLocation={'path':str(app)})
 (dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
elif not dest.exists():
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.import-',dir=parent))
 try:
  shutil.copytree(a.app,stage/a.app.name,symlinks=True)
  assert sha(stage/relative)==hash
  if not source_signature:
   # Some local archives expanded framework symlinks into duplicate files.
   for framework in (stage/a.app.name/'Contents/Frameworks').glob('*.framework'):
    versions=framework/'Versions';current=versions/'Current'
    if versions.exists():
     if current.is_dir() and not current.is_symlink():
      actual=next((v for v in versions.iterdir() if v.name!='Current' and v.is_dir()),None)
      if actual:shutil.rmtree(current);current.symlink_to(actual.name)
     for name in [framework.stem,'Resources','Headers']:
      item=framework/name
      if (current/name).exists() and item.exists() and not item.is_symlink():
       if item.is_dir():shutil.rmtree(item)
       else:item.unlink()
       item.symlink_to('Versions/Current/'+name)
  if not source_signature:subprocess.run(['codesign','--force','--deep','--sign','-','--preserve-metadata=entitlements',str(stage/a.app.name)],check=True)
  imported_hash=sha(stage/relative)
  subprocess.run(['codesign','--verify','--deep',str(stage/a.app.name)],check=True)
  manifest=dict(id=a.engine,platforms=platforms[a.engine],version=version,upstream=a.upstream or ('https://git.eden-emu.dev/eden-emu/eden' if a.engine=='eden' else 'https://github.com/'+upstream),revision=a.release or info.get('CFBundleShortVersionString','local'),integrationRevision='1',architecture='arm64' if 'arm64' in archs else 'x86_64',library=str(relative),sha256=imported_hash,capabilities=['nativeWindow','localImport','gameUntested']+(['requiresRosetta'] if 'arm64' not in archs else []),channel='github-release' if a.release else 'local-import',validated=True,license='See imported bundle notices; local use only')
  (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
  (stage/'provenance.json').write_text(json.dumps(dict(source=str(a.app),sourceSignatureValid=source_signature,sourceBinarySHA256=hash,binarySHA256=imported_hash,validation='Mach-O architecture, bundle signature and copied executable integrity only; game boot explicitly deferred by user.'),indent=2)+'\n')
  stage.rename(dest)
 except:shutil.rmtree(stage);raise
selection=parent/'selection.json';old=json.loads(selection.read_text()) if selection.exists() else {}
if not a.no_activate and old.get('current')!=version:selection.write_text(json.dumps(dict(current=version,previous=old.get('current')),indent=2)+'\n')
print(a.engine,version,'installed; game untested')

if a.result_file:a.result_file.write_text((dest/'manifest.json').read_text())
