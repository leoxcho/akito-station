#!/usr/bin/env python3
"""Build recorded upstream source, validate a user ROM in isolation, stage and activate.
Never edits ROMs, existing emulator applications, or their data.
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, tempfile, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
RECIPES={
 'ppsspp':dict(repo='https://github.com/hrydgard/ppsspp',source='ppsspp',binary='build-arm/lib/ppsspp_libretro.dylib',license='GPL-2.0-or-later',notice='LICENSE.TXT',commands=[['cmake','-S','.','-B','build-arm','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=arm64','-DLIBRETRO=ON','-DHEADLESS=OFF','-DUNITTEST=OFF','-DATLAS_TOOL=OFF','-DUSE_DISCORD=OFF','-DUSE_MINIUPNPC=OFF','-DUSE_SYSTEM_LIBPNG=OFF','-DUSE_SYSTEM_ZSTD=OFF','-DUSE_SYSTEM_FFMPEG=OFF','-DBUILD_BUNDLED_FFMPEG=ON'],['cmake','--build','build-arm','--target','ppsspp_libretro','-j8']]),
 'genesis_plus_gx':dict(repo='https://github.com/libretro/Genesis-Plus-GX',source='genesis-plus-gx',binary='genesis_plus_gx_libretro.dylib',license='Non-commercial (see LICENSE)',notice='LICENSE.txt',commands=[['make','-f','Makefile.libretro','-j8','platform=osx','ARCHFLAGS=-arch arm64']]),
 'mednafen_pce_fast':dict(repo='https://github.com/libretro/beetle-pce-fast-libretro',source='beetle-pce-fast',binary='mednafen_pce_fast_libretro.dylib',license='GPL-2.0-or-later',notice='COPYING',commands=[['make','-j8','platform=osx']]),
 'parallel_n64':dict(repo='https://github.com/libretro/parallel-n64',source='parallel-n64',binary='parallel_n64_libretro.dylib',license='GPL-2.0-or-later',notice='mupen64plus-rsp-cxd4/COPYING',commands=[['make','-j8','platform=osx','ARCH=arm64','ARCHFLAGS=-arch arm64','HAVE_OPENGL=0','HAVE_GLIDE64=0','HAVE_GLIDEN64=0','HAVE_GLN64=0','HAVE_RICE=0','HAVE_PARALLEL=0','HAVE_PARALLEL_RSP=0','WITH_DYNAREC=aarch64']]),
 'nestopia':dict(repo='https://github.com/libretro/nestopia',source='nestopia',binary='libretro/nestopia_libretro.dylib',license='GPL-2.0',notice='COPYING',commands=[['make','-C','libretro','-j8','platform=osx','ARCH=arm64']]),
 'gambatte':dict(repo='https://github.com/libretro/gambatte-libretro',source='gambatte',binary='gambatte_libretro.dylib',license='GPL-2.0',notice='COPYING',commands=[['make','-f','Makefile.libretro','-j8','platform=osx','ARCHFLAGS=-arch arm64']]),
 'snes9x':dict(repo='https://github.com/snes9xgit/snes9x',source='snes9x',binary='libretro/snes9x_libretro.dylib',license='Snes9x non-commercial',notice='LICENSE',commands=[['make','-C','libretro','-j8','platform=osx','ARCH=arm64']]),
 'mgba':dict(repo='https://github.com/mgba-emu/mgba',source='mgba',binary='build-arm/mgba_libretro.dylib',license='MPL-2.0',notice='LICENSE',commands=[['cmake','-S','.','-B','build-arm','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=arm64','-DBUILD_LIBRETRO=ON','-DBUILD_QT=OFF','-DBUILD_SDL=OFF','-DBUILD_GL=OFF','-DBUILD_GLES2=OFF','-DBUILD_GLES3=OFF','-DUSE_FFMPEG=OFF','-DUSE_LIBZIP=OFF','-DUSE_SQLITE3=OFF','-DUSE_LZMA=OFF','-DUSE_PNG=OFF','-DUSE_ZLIB=OFF','-DBUILD_SHARED=OFF'],['cmake','--build','build-arm','--target','mgba_libretro','-j8']]),
 'pcsx_rearmed':dict(repo='https://github.com/libretro/pcsx_rearmed',source='pcsx_rearmed',binary='pcsx_rearmed_libretro.dylib',license='GPL-2.0',notice='COPYING',commands=[['make','-f','Makefile.libretro','-j8','platform=osx','ARCH=arm64']]),
 'melondsds':dict(repo='https://github.com/JesseTG/melonds-ds',source='melonds-ds',binary='build-arm/src/libretro/melondsds_libretro.dylib',license='GPL-3.0-or-later',notice='LICENSE',commands=[['cmake','-S','.','-B','build-arm','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=arm64','-DENABLE_OPENGL=OFF','-DENABLE_JIT=OFF','-DENABLE_NETWORKING=ON','-DBUILD_TESTING=OFF'],['cmake','--build','build-arm','-j8']])}
def run(command,cwd=None,**kw):return subprocess.run(command,cwd=cwd,check=True,**kw)
def sha(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  while data:=f.read(1048576):h.update(data)
 return h.hexdigest()
def atomic_json(path,value):
 path.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,delete=False) as f:json.dump(value,f,indent=2,sort_keys=True);f.flush();os.fsync(f.fileno());tmp=f.name
 os.replace(tmp,path)
def verify(root,core,version):
 if any(x in ('','.','..') or '/' in x or '\\' in x for x in (core,version)):raise ValueError('Unsafe runtime identifier')
 folder=root/core/version;m=json.loads((folder/'manifest.json').read_text())
 if pathlib.Path(m['library']).name!=m['library']:raise ValueError('Invalid binary path')
 if not m['validated'] or m['architecture']!='arm64' or sha(folder/m['library'])!=m['sha256']:raise ValueError('Unvalidated or corrupted runtime')
 return m
def activate(root,core,version):
 verify(root,core,version);sel=root/core/'selection.json';old=json.loads(sel.read_text()) if sel.exists() else {}
 if old.get('current')!=version:atomic_json(sel,dict(current=version,previous=old.get('current')))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('operation',choices=['build','stage','rollback','check']);p.add_argument('--core',choices=RECIPES,required=True);p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--rom',type=pathlib.Path);p.add_argument('--revision');p.add_argument('--work',type=pathlib.Path);p.add_argument('--host',type=pathlib.Path,default=pathlib.Path('/tmp/akito-station-native-build/release/AkitoStation'));p.add_argument('--activate',action='store_true');p.add_argument('--abi-only',action='store_true',help='Native ABI validation when no user game is available');p.add_argument('--frames',type=int,default=600);a=p.parse_args();a.root=a.root.resolve();r=RECIPES[a.core]
 if not a.root.is_dir():raise ValueError('Configured runtime root must already exist; reconnect its volume if missing')
 if a.operation=='rollback':
  s=json.loads((a.root/a.core/'selection.json').read_text());previous=s.get('previous')
  if not previous:raise ValueError('No previous validated runtime')
  activate(a.root,a.core,previous);return
 if a.operation=='check':
  import urllib.request
  req=urllib.request.Request(r['repo'].replace('https://github.com/','https://api.github.com/repos/')+'/releases',headers={'User-Agent':'AkitoStation'})
  with urllib.request.urlopen(req,timeout=30) as response:print(response.read().decode())
  return
 if not a.abi_only and (not a.rom or not a.rom.is_file()):raise ValueError('A user-supplied ROM is required for boot validation')
 source=ROOT/'Vendor'/r['source']
 if a.operation=='build':
  raise ValueError('Source adapter builds are unavailable in the initial publication; import a compatible external runtime instead.')
  if not a.revision:
   lockpath=ROOT/'Resources/upstreams.lock.json'
   if not lockpath.exists():lockpath=ROOT/'upstreams.lock.json'
   lock=json.loads(lockpath.read_text());a.revision=lock[a.core]['revision']
  # A fresh checkout for each update avoids changing known-good source or artifacts.
  work=a.work or (a.root.parent/'downloads')
  if not work.is_dir():raise ValueError('Configured build-data directory is unavailable')
  source=work/('candidate-'+a.core+'-'+str(time.time_ns()))
  run(['git','clone','--filter=blob:none','--no-checkout',r['repo'],str(source)])
  run(['git','checkout','--detach',a.revision],cwd=source);run(['git','submodule','update','--init','--recursive','--depth','1'],cwd=source)
  patch=ROOT/'Patches'/(a.core+'-arm.patch')
  if not patch.exists():patch=pathlib.Path(__file__).parent/(a.core+'-arm.patch')
  if patch.exists():run(['git','apply',str(patch)],cwd=source)
  for command in r['commands']:run(command,cwd=source)
 binary=source/r['binary'];arch=subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()
 if 'arm64' not in arch.split():raise ValueError('Runtime is not native ARM64')
 dependencies=subprocess.check_output(['otool','-L',str(binary)],text=True)
 for line in dependencies.splitlines()[1:]:
  dep=line.strip().split(' (')[0]
  if dep.startswith('/') and not dep.startswith(('/System/Library/','/usr/lib/')):raise ValueError('Unbundled runtime dependency: '+dep)
 revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip();version=revision[:12]+'-arm1';final=a.root/a.core/version
 if final.exists():
  verify(a.root,a.core,version)
  if a.activate:activate(a.root,a.core,version)
  print('Already validated:',final);return
 staging_root=a.root.parent/'.runtime-staging';staging_root.mkdir(parents=True,exist_ok=True)
 staging=pathlib.Path(tempfile.mkdtemp(prefix=a.core+'-',dir=staging_root));shutil.copy2(binary,staging/binary.name)
 try:
  run(['codesign','--force','--sign','-',str(staging/binary.name)])
  if a.core=='ppsspp':shutil.copytree(source/'assets',staging/'PPSSPP')
  if a.abi_only:
   run([str(a.host.resolve()),'--verify-runtime-core','--core',str(staging/binary.name)])
  else:
   with open(staging/'boot.log','w') as log:run([str(a.host.resolve()),'--probe','--core',str(staging/binary.name),'--rom',str(a.rom.resolve()),'--output',str(staging/'validation'),'--frames',str(a.frames),'--system',str(staging)],stdout=log,stderr=log,timeout=180)
   # A rendered frame and save-state round trip prove basic integration, not full compatibility.
   report=json.loads((staging/'validation/report.json').read_text())
   if report['frames']<30 or report['uniqueColors']<2 or not report['loadState']:raise ValueError('Boot validation did not pass')
   # Remove game-derived framebuffer/state from runtime packages; preserve report and log locally.
   for file in (staging/'validation').iterdir():
    if file.name!='report.json':
     if file.is_dir():shutil.rmtree(file)
     else:file.unlink()
   report['rom']=a.rom.name;atomic_json(staging/'validation/report.json',report)
  notice=source/r['notice']
  if not notice.exists():
   choices=list(source.glob('LICENSE*'))+list(source.glob('COPYING*'))
   if not choices:raise ValueError('Upstream license notice missing')
   notice=choices[0]
  shutil.copy2(notice,staging/'LICENSE.upstream')
  # Exact tracked upstream source accompanies the binary. Build-generated files and user ROMs are excluded.
  run(['git','archive','--format=tar.gz','--output',str(staging/'source.tar.gz'),'HEAD'],cwd=source)
  patch=ROOT/'Patches'/(a.core+'-arm.patch')
  if not patch.exists():patch=pathlib.Path(__file__).parent/(a.core+'-arm.patch')
  if patch.exists():shutil.copy2(patch,staging/patch.name)
  deps={}
  depdir=source/'build-arm/_deps'
  if depdir.exists():
   for dep in depdir.glob('*-src'):
    if (dep/'.git').exists():
     rev=subprocess.check_output(['git','rev-parse','HEAD'],cwd=dep,text=True).strip();deps[dep.name]=rev
     run(['git','archive','--format=tar.gz','--output',str(staging/(dep.name+'.tar.gz')),'HEAD'],cwd=dep)
  submodules=subprocess.check_output(['git','submodule','status','--recursive'],cwd=source,text=True).splitlines()
  if submodules:
   archives=staging/'source-dependencies';archives.mkdir()
   for line in submodules:
    parts=line.strip().split();dependency_revision,path=parts[:2];deps[path]=dependency_revision
    run(['git','archive','--format=tar.gz','--output',str(archives/(hashlib.sha256(path.encode()).hexdigest()[:16]+'.tar.gz')),'HEAD'],cwd=source/path)
  manifest=dict(id=a.core,version=version,upstream=r['repo'],revision=revision,integrationRevision='1',architecture='arm64',library=binary.name,sha256=sha(staging/binary.name),capabilities=['softwareVideo','audio','joypad','saveStates','sram']+(['abiOnly'] if a.abi_only else ['bootVerified']),channel='source-pinned',validated=True,license=r['license'])
  atomic_json(staging/'manifest.json',manifest);atomic_json(staging/'build.json',dict(commands=r['commands'],dependencies=deps,validation='Native ABI load only; no game tested' if a.abi_only else 'Video output and save-state round trip; not full-game compatibility',sourceSHA256=sha(staging/'source.tar.gz')))
  final.parent.mkdir(parents=True,exist_ok=True);os.rename(staging,final)
  if a.activate:activate(a.root,a.core,version)
  print('Validated runtime:',final)
 except BaseException:
  print('Candidate failed. Current runtime unchanged. Evidence:',staging);raise
if __name__=='__main__':main()
