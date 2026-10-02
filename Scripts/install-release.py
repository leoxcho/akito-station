#!/usr/bin/env python3
"""Stage a GitHub release app without executing it or changing the active runtime."""
import argparse,json,os,pathlib,shutil,subprocess,sys,tempfile

def safe_member(name):
 p=pathlib.PurePosixPath(name)
 if p.is_absolute() or '..' in p.parts or '\\' in name:
  raise ValueError('Archive contains an unsafe path: '+name)

def validate_bundle(app):
 root=app.resolve()
 for parent,dirs,files in os.walk(app,followlinks=False):
  for name in dirs+files:
   item=pathlib.Path(parent)/name
   if item.is_symlink():
    target=item.resolve()
    if root!=target and root not in target.parents:raise ValueError('App contains an escaping symbolic link')
   elif not item.is_dir() and not item.is_file():raise ValueError('App contains a special file')

def main():
 p=argparse.ArgumentParser();p.add_argument('--archive',type=pathlib.Path,required=True);p.add_argument('--engine',required=True);p.add_argument('--root',type=pathlib.Path,required=True);p.add_argument('--repository',required=True);p.add_argument('--release',required=True);p.add_argument('--result-file',required=True);a=p.parse_args()
 if not a.root.is_dir():raise ValueError('Runtime storage is unavailable')
 stage=pathlib.Path(tempfile.mkdtemp(prefix='.release-',dir=a.archive.parent));mounted=False
 try:
  if a.archive.suffix.lower()=='.dmg':
   extract=stage/'volume';extract.mkdir()
   subprocess.run(['/usr/bin/hdiutil','attach','-readonly','-nobrowse','-noautoopen','-mountpoint',str(extract),str(a.archive)],check=True);mounted=True
  else:
   extract=stage/'files';extract.mkdir()
   # libarchive handles ZIP, tar and 7z. Its default extraction also refuses writes through symlinks.
   listing=subprocess.check_output(['/usr/bin/tar','-tf',str(a.archive)],text=True)
   for name in listing.splitlines():safe_member(name)
   subprocess.run(['/usr/bin/tar','-xf',str(a.archive),'-C',str(extract)],check=True)
  apps=[]
  for parent,dirs,files in os.walk(extract,followlinks=False):
   for name in list(dirs):
    path=pathlib.Path(parent)/name
    if name.endswith('.app') and not path.is_symlink():apps.append(path);dirs.remove(name)
  if len(apps)!=1:raise ValueError('Choose a macOS release containing exactly one emulator app; found '+str(len(apps)))
  validate_bundle(apps[0])
  subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('import-managed.py')),'--engine',a.engine,'--app',str(apps[0]),'--root',str(a.root),'--no-activate','--require-signature','--upstream',a.repository,'--release',a.release,'--result-file',a.result_file],check=True)
 finally:
  if mounted:
   detached=subprocess.run(['/usr/bin/hdiutil','detach',str(stage/'volume')]).returncode==0
   if not detached:raise RuntimeError('Could not unmount release image; temporary files retained at '+str(stage))
  shutil.rmtree(stage)
if __name__=='__main__':main()
