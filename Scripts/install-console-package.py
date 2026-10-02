#!/usr/bin/env python3
"""Install supplied console content in isolation, then publish into the selected ROM library.
License bytes are never printed. No keys or licenses are fetched or generated.
"""
import argparse,base64,gzip,hashlib,json,os,pathlib,re,shutil,struct,subprocess,tempfile,uuid,zlib
ID=re.compile(r'^[A-Z]{2}[0-9]{4}-[A-Z0-9]{9}_[0-9]{2}-[A-Za-z0-9_-]{1,32}$')

def inspect_package(path):
 if path.is_symlink() or not path.is_file() or path.name.startswith('._'):raise ValueError('Choose a regular console package')
 size=path.stat().st_size
 with path.open('rb') as f:
  header=f.read(256)
  if len(header)<192:raise ValueError('Incomplete package header')
  if header[:4]==b'\x7fCNT':return 'ps4','',0
  if header[:4]!=b'\x7fPKG':raise ValueError('Unrecognized console package')
  family=struct.unpack_from('>H',header,6)[0];offset,count=struct.unpack_from('>II',header,8)
  total,data_offset,data_size=struct.unpack_from('>QQQ',header,24)
  if total>size or total<192 or data_offset>total or data_size>total-data_offset or count>4096:raise ValueError('Invalid package data ranges')
  content=header[48:96].split(b'\0',1)[0].decode('ascii')
  if not ID.fullmatch(content):raise ValueError('Invalid package content ID')
  content_type=0
  for _ in range(count):
   if offset+8>total:raise ValueError('Invalid metadata offset')
   f.seek(offset);record=f.read(12)
   if len(record)<8:raise ValueError('Truncated metadata')
   kind,length=struct.unpack_from('>II',record)
   if length>total-offset-8:raise ValueError('Invalid metadata length')
   if kind==2 and length>=4 and len(record)==12:content_type=struct.unpack_from('>I',record,8)[0]
   offset+=8+length
  vita=content_type in (0x15,0x16,0x17,0x1f)
  if family==1 and not vita and not content[7:].startswith('PCS'):return 'ps3',content,content_type
  if family==2 and vita and content[7:].startswith('PCS'):return 'psvita',content,content_type
  raise ValueError('Package family and content type disagree or belong to an unsupported console')

def validate_tree(root):
 for parent,dirs,files in os.walk(root,followlinks=False):
  for name in dirs+files:
   p=pathlib.Path(parent)/name
   if p.is_symlink() or (not p.is_dir() and not p.is_file()):raise ValueError('Installed content contains a symbolic link or special file')

def copy_verified(source,target):
 if source.is_dir():
  validate_tree(source);shutil.copytree(source,target)
  for item in source.rglob('*'):
   if item.is_file():verify(item,target/item.relative_to(source))
 else:shutil.copy2(source,target);verify(source,target)

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.digest()

def verify(a,b):
 if digest(a)!=digest(b):raise ValueError('Copy verification failed')

def publish(source,target,platform,title):
 """Merge only in a new sibling; retain the prior title directory on commit."""
 target.parent.mkdir(parents=True,exist_ok=True)
 if target.is_symlink():raise ValueError('ROM installation destination is a symbolic link')
 if target.exists():
  marker=target/'.arm-install.json'
  if not marker.is_file() or json.loads(marker.read_text()).get('platform')!=platform:raise ValueError('An existing non-Akito Station game occupies this destination; originals were preserved')
 prepared=pathlib.Path(tempfile.mkdtemp(prefix='.prepare-',dir=target.parent));prepared.rmdir()
 backup=None
 try:
  if target.exists():copy_verified(target,prepared)
  else:prepared.mkdir()
  validate_tree(source)
  for item in source.rglob('*'):
   out=prepared/item.relative_to(source)
   if item.is_dir():out.mkdir(parents=True,exist_ok=True)
   else:
    out.parent.mkdir(parents=True,exist_ok=True)
    if out.is_dir():raise ValueError('Update has a conflicting file type')
    shutil.copy2(item,out);verify(item,out)
  (prepared/'.arm-install.json').write_text(json.dumps(dict(platform=platform,titleID=title)))
  if target.exists():
   backups=target.parent/'.arm-backups';backups.mkdir(exist_ok=True);backup=backups/(title+'-'+uuid.uuid4().hex);target.rename(backup)
  try:prepared.rename(target)
  except:
   if backup:backup.rename(target)
   raise
  return backup
 finally:
  if prepared.exists():shutil.rmtree(prepared)

def link_game(source,target):
 target.parent.mkdir(parents=True,exist_ok=True)
 if target.is_symlink() and target.resolve()==source.resolve():return False,None
 backup=None
 if target.exists() or target.is_symlink():
  backups=target.parent/'.arm-backups';backups.mkdir(exist_ok=True)
  backup=backups/(target.name+'-'+uuid.uuid4().hex);target.rename(backup)
 try:target.symlink_to(source,target_is_directory=True)
 except:
  if backup:backup.rename(target)
  raise
 return True,backup

def run_installer(command,env,cwd,log):
 # Do not print argv: the Vita command carries the user's encoded license.
 with log.open('wb') as out:
  try:result=subprocess.run(command,env=env,cwd=cwd,stdout=out,stderr=out,timeout=1800)
  except subprocess.TimeoutExpired:raise ValueError('Runtime installer timed out; temporary output retained') from None
 return result.returncode

def read_logs(stage):
 text=''
 for path in stage.rglob('*.log*'):
  if path.is_file() and path.stat().st_size<16*1024*1024:
   try:
    data=gzip.open(path,'rb').read(16*1024*1024) if path.suffix=='.gz' else path.read_bytes()
    text+=data.decode('utf-8','replace')
   except (OSError,EOFError):pass
 return text

def main():
 p=argparse.ArgumentParser();p.add_argument('--package',type=pathlib.Path,required=True);p.add_argument('--platform',choices=['ps3','ps4','psvita'],required=True);p.add_argument('--library',type=pathlib.Path,required=True);p.add_argument('--data',type=pathlib.Path,required=True);p.add_argument('--runtime',type=pathlib.Path);p.add_argument('--work',type=pathlib.Path,required=True);p.add_argument('--license',type=pathlib.Path);p.add_argument('--result',type=pathlib.Path,required=True);p.add_argument('--folder',action='store_true');a=p.parse_args()
 if not a.library.is_dir() or not a.work.is_dir():raise ValueError('Reconnect the selected ROM library and build-data volumes')
 if not a.folder:
  platform,content,content_type=inspect_package(a.package)
  if platform!=a.platform:raise ValueError('Package is for '+platform+', not '+a.platform)
  if platform=='ps4':raise ValueError('Current shadPS4 has no PKG installation interface. Import an extracted PS4 game folder instead.')
 a.library=a.library.resolve();a.data=a.data.resolve()
 if a.library.name.lower() in ('ps3','ps4','psvita') and a.library.name.lower()!=a.platform:raise ValueError('Choose the common ROM root or the matching console folder')
 console=a.library if a.library.name.lower()==a.platform else a.library/a.platform
 console.mkdir(parents=True,exist_ok=True)
 if a.library!=console.resolve() and a.library not in console.resolve().parents:raise ValueError('Console folder escapes the selected ROM library')
 if a.folder:
  if a.platform!='ps4':raise ValueError('Extracted-folder installation currently supports PS4')
  # The caller supplies a title ID already validated from PARAM.SFO; re-read it independently here.
  sfo=a.package/'sce_sys/param.sfo'
  if not sfo.is_file() or not (a.package/'eboot.bin').is_file():raise ValueError('Not an extracted PS4 game folder')
  blob=sfo.read_bytes()
  if len(blob)<20 or len(blob)>1048576 or blob[:4]!=b'\0PSF':raise ValueError('Invalid PS4 PARAM.SFO')
  keys,values,count=struct.unpack_from('<III',blob,8);title=''
  if count>4096 or 20+16*count>len(blob):raise ValueError('Invalid PS4 PARAM.SFO entries')
  for i in range(count):
   key,fmt,length,maximum,value=struct.unpack_from('<HHIII',blob,20+16*i)
   if keys+key>=len(blob) or values+value+length>len(blob):raise ValueError('Invalid PS4 PARAM.SFO ranges')
   name=blob[keys+key:].split(b'\0',1)[0]
   if name==b'TITLE_ID':title=blob[values+value:values+value+length].split(b'\0',1)[0].decode('ascii')
  if not re.fullmatch(r'CUSA\d{5}',title):raise ValueError('Selected folder is not a PS4 CUSA title')
  destination=console/title;backup=publish(a.package,destination,a.platform,title)
  a.result.write_text(json.dumps(dict(platform=a.platform,titleID=title,destination=str(destination),status='Installed extracted PS4 game',backup=str(backup) if backup else None)));return
 platform,content,content_type=inspect_package(a.package)
 if platform!=a.platform:raise ValueError('Package is for '+platform+', not '+a.platform)
 if platform=='ps4':raise ValueError('Current shadPS4 has no PKG installation interface. Import an extracted PS4 game folder instead.')
 if not a.runtime or not a.runtime.is_file():raise ValueError('Install a validated runtime first')
 title=content[7:16]
 # A per-run HOME/config prevents the runtime installer writing to the user's emulator or live game data.
 stage=pathlib.Path(tempfile.mkdtemp(prefix='package-'+platform+'-',dir=a.work));home=stage/'home';home.mkdir()
 env=dict(os.environ,HOME=str(home),CFFIXED_USER_HOME=str(home),XDG_CONFIG_HOME=str(home/'.config'),XDG_DATA_HOME=str(home/'.local/share'),XDG_CACHE_HOME=str(stage/'cache'))
 log=stage/'installer.log';outputs=[]
 if platform=='ps3':
  firmware=a.data/'dev_flash'
  if not (firmware/'sys/external/liblv2.sprx').is_file():raise ValueError('Install PS3 firmware into Akito Station managed PS3 storage first')
  config=home/'Library/Application Support/rpcs3';config.mkdir(parents=True,exist_ok=True)
  copy_verified(firmware,config/'dev_flash')
  exit_code=run_installer([str(a.runtime),'--headless','--installpkg',str(a.package.resolve())],env,stage,log)
  source=home/'Library/Application Support/rpcs3/dev_hdd0/game'/title
  logs=read_logs(stage)
  completion='Successfully installed '+str(a.package.resolve())+' (title_id='+title+','
  if not source.is_dir() or completion not in logs or (exit_code and 'manual_typemap' not in logs):raise ValueError('RPCS3 did not confirm installation; live games are unchanged. Evidence: '+str(stage))
  outputs=[(source,console/title,a.data/'home/Library/Application Support/rpcs3/dev_hdd0/game'/title)]
 else:
  license_file=a.license or a.data/'fs/ux0/license'/title/(content+'.rif')
  if not license_file.is_file() or license_file.is_symlink() or license_file.stat().st_size!=512:raise ValueError('Choose the matching 512-byte Vita work.bin or RIF license')
  license_data=license_file.read_bytes()
  if license_data[16:64].split(b'\0',1)[0].decode('ascii')!=content:raise ValueError('Vita license content ID does not match this package')
  # zRIF is a lossless zlib+base64 representation of the supplied RIF, not a new license.
  zrif=base64.b64encode(zlib.compress(license_data,9)).decode('ascii')
  fs=stage/'fs';fs.mkdir()
  default=home/'Library/Application Support/Vita3K/Vita3K';default.mkdir(parents=True)
  run_installer([str(a.runtime),'--help'],env,stage,stage/'configuration.log')
  config=default/'config.yml'
  if not config.is_file() or 'keyboard-button-select' not in config.read_text():raise ValueError('Runtime did not create a complete configuration in isolated HOME')
  lines=config.read_text().splitlines();lines=[line for line in lines if not line.startswith('pref-path:')]
  lines.append('pref-path: '+json.dumps(str(fs)+'/'));config.write_text('\n'.join(lines)+'\n')
  if (a.runtime.parent/'config.yml').exists() or (a.runtime.parent/'portable').exists():raise ValueError('Runtime has a portable configuration; package isolation cannot be guaranteed')
  exit_code=run_installer([str(a.runtime),'--console','--pkg',str(a.package.resolve()),'--zrif',zrif],env,stage,log)
  logs=read_logs(stage)
  if exit_code or any(token in logs for token in ['|E|','|C|','[error]','[critical]']):raise ValueError('Vita installer reported an error; live games are unchanged. Evidence: '+str(stage))
  for area in ['app','patch','addcont','theme']:
   source=fs/'ux0'/area/title
   if source.is_dir():
    dest=console/title if area=='app' else console/'.content'/area/title
    outputs.append((source,dest,a.data/'fs/ux0'/area/title))
  if not outputs:raise ValueError('Vita installer produced no matching title in isolated storage. Evidence: '+str(stage))
  for source,dest,target in outputs:
   if source.parent.name=='app' and (not (source/'eboot.bin').is_file() or not (source/'sce_sys/param.sfo').is_file()):raise ValueError('Vita installation is incomplete')
  dest_license=a.data/'fs/ux0/license'/title/(content+'.rif');dest_license.parent.mkdir(parents=True,exist_ok=True)
  if dest_license.exists() and dest_license.read_bytes()!=license_data:raise ValueError('A different Vita license is already installed')
  if not dest_license.exists():dest_license.write_bytes(license_data);dest_license.chmod(0o600)
 for source,dest,target in outputs:
  validate_tree(source)
  if a.data!=target.parent.resolve() and a.data not in target.parent.resolve().parents:raise ValueError('Runtime game path escapes Akito Station system storage')
  if dest.is_symlink():raise ValueError('Destination is a symbolic link; existing data was preserved')
 installed=[];committed=[];linked=[]
 try:
  for source,dest,target in outputs:
   backup=publish(source,dest,platform,title);committed.append((dest,backup))
   changed,prior=link_game(dest,target)
   if changed:linked.append((target,prior))
   installed.append(dict(path=str(dest),backup=str(backup) if backup else None))
 except:
  for target,prior in reversed(linked):
   target.unlink()
   if prior:prior.rename(target)
  for dest,backup in reversed(committed):
   dest.rename(dest.parent/('.failed-install-'+uuid.uuid4().hex))
   if backup:backup.rename(dest)
  raise

 a.result.write_text(json.dumps(dict(platform=platform,titleID=title,destination=str(outputs[0][1]),status='Installed package; gameplay untested',installed=installed,evidence=str(stage))))
 print('Installed '+platform+' package in selected ROM library')
if __name__=='__main__':main()
