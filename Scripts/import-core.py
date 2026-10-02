#!/usr/bin/env python3
"""Register or copy a user-owned core after isolated native ABI verification."""
import argparse,hashlib,json,pathlib,shutil,subprocess,tempfile,os
p=argparse.ArgumentParser();p.add_argument('--engine',required=True);p.add_argument('--platform',required=True);p.add_argument('--binary',type=pathlib.Path,required=True);p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--host',type=pathlib.Path,required=True);p.add_argument('--upstream',required=True);p.add_argument('--license',required=True);p.add_argument('--external',action='store_true');a=p.parse_args()
platforms={'nestopia':['nes'],'snes9x':['snes'],'gambatte':['gb','gbc'],'mgba':['gba','gb','gbc'],'genesis_plus_gx':['genesis'],'mednafen_pce_fast':['pce'],'parallel_n64':['n64'],'melondsds':['nds'],'pcsx_rearmed':['ps1'],'ppsspp':['psp'],'beetle_saturn':['saturn']}
if a.platform not in platforms.get(a.engine,[]):raise ValueError('Wrong console for core')
binary=a.binary.resolve();root=a.root.resolve()
if root==binary.parent or root in binary.parents:raise ValueError('Select an original core outside managed runtime storage')
if binary.suffix!='.dylib' or not binary.is_file():raise ValueError('Choose a macOS libretro dylib')
if 'arm64' not in subprocess.check_output(['lipo','-archs',str(binary)],text=True).split():raise ValueError('Core must support Apple Silicon')
subprocess.run([str(a.host),'--verify-runtime-core','--core',str(binary)],check=True,timeout=30)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
version=sha(binary)[:12]+('-external' if a.external else '-local1');parent=root/a.engine;parent.mkdir(parents=True,exist_ok=True);dest=parent/version
if not dest.exists():
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.core-',dir=parent))
 try:
  if not a.external:
   shutil.copy2(binary,stage/binary.name)
   if a.engine=='ppsspp':
    assets=binary.parent/'PPSSPP'
    if not (assets/'compat.ini').is_file():raise ValueError('PPSSPP core requires adjacent official PPSSPP assets')
    shutil.copytree(assets,stage/'PPSSPP',symlinks=False)
  m=dict(id=a.engine,platforms=platforms[a.engine],version=version,upstream=a.upstream,revision='local',integrationRevision='1',architecture='arm64',library=binary.name,sha256=sha(binary),capabilities=['libretro','softwareVideo','abiOnly','gameUntested'],channel='external' if a.external else 'local-import',validated=True,license=a.license)
  if a.external:m['externalLocation']={'path':str(binary.parent)};m['capabilities'].append('externalRuntime')
  (stage/'manifest.json').write_text(json.dumps(m,indent=2));stage.rename(dest)
 except:shutil.rmtree(stage);raise
selection=parent/'selection.json';old=json.loads(selection.read_text()) if selection.exists() else {}
if old.get('current')!=version:
 temp=parent/'.selection.tmp';temp.write_text(json.dumps(dict(current=version,previous=old.get('current'))));os.replace(temp,selection)
print(a.engine,version,'registered' if a.external else 'installed','ABI checked; game untested')
