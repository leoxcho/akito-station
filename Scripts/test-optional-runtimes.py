#!/usr/bin/env python3
"""Self-authored fixtures verify Public managed and external lifecycle without games."""
from pathlib import Path
import hashlib,json,plistlib,subprocess,sys,tempfile
source=Path(__file__).resolve().parents[1]
app=source.parent.parent/'Akito Station.app'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def run(args):return subprocess.run(list(map(str,args)),capture_output=True,text=True)
results=[]
with tempfile.TemporaryDirectory(prefix='akito-optional-fixtures-') as temporary:
 root=Path(temporary)
 c=root/'fixture.c';c.write_text('int main(int argc,char**argv){return argc>1?0:1;}')
 for tool in [source/'Scripts/import-managed.py',app/'Contents/Resources/Tools/import-managed.py']:
  for engine,platform in [('rpcs3','ps3'),('ppsspp_sdl','psp'),('pcsx2','ps2'),('vita3k','psvita'),('eden','switchConsole'),('shadps4','ps4'),('azahar','n3ds'),('dolphin_app','wii'),('flycast','dreamcast')]:
   original=root/(tool.parent.parent.name+'-'+engine)/'Original.app';binary=original/'Contents/MacOS/Fixture';binary.parent.mkdir(parents=True)
   (original/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='Fixture',CFBundleIdentifier='net.pcsx2.pcsx2' if engine=='pcsx2' else 'test.akito.'+engine,CFBundleShortVersionString='fixture-1',CFBundlePackageType='APPL')))
   subprocess.run(['xcrun','clang','-arch','arm64',str(c),'-o',str(binary)],check=True)
   subprocess.run(['codesign','--force','--sign','-',str(original)],check=True,capture_output=True)
   before=sha(binary);runtime=root/(tool.parent.parent.name+'-'+engine)/'runtimes';runtime.mkdir()
   args=[sys.executable,tool,'--engine',engine,'--platform',platform,'--app',original,'--root',runtime,'--require-signature']
   registered=run(args+['--register-external']);assert registered.returncode==0,registered.stderr
   selected=json.loads((runtime/engine/'selection.json').read_text())['current'];manifest=json.loads((runtime/engine/selected/'manifest.json').read_text())
   assert manifest['externalLocation']['path']==str(original.resolve());assert manifest['library']=='Contents/MacOS/Fixture'
   assert not list((runtime/engine/selected).rglob('*.app'))
   assert run([binary,'/tmp/User Games/Fixture.iso']).returncode==0
   copied=run(args);assert copied.returncode==0,copied.stderr
   active=json.loads((runtime/engine/'selection.json').read_text());managed=json.loads((runtime/engine/active['current']/'manifest.json').read_text());assert active['previous']==selected and 'externalLocation' not in managed
   assert managed['sha256']==sha(runtime/engine/active['current']/managed['library']) and sha(binary)==before
   results.append(dict(tool='packaged' if tool.is_relative_to(app) else 'source',engine=engine,external_registration=True,external_files_unchanged=True,managed_install=True,version_selection=True,fixture_launch=True))
 # Native ABI fixture contains no emulator implementation or copyrighted content.
 core=root/'fixture.dylib';code=root/'core.c'
 functions=['retro_init','retro_deinit','retro_load_game','retro_unload_game','retro_run','retro_get_system_info','retro_get_system_av_info','retro_set_environment','retro_set_video_refresh','retro_set_input_state','retro_set_input_poll','retro_serialize','retro_unserialize']
 code.write_text('unsigned retro_api_version(void){return 1;}\n'+'\n'.join('void '+name+'(void){}' for name in functions))
 subprocess.run(['xcrun','clang','-dynamiclib','-arch','arm64',str(code),'-o',str(core)],check=True)
 for tool in [source/'Scripts/import-core.py',app/'Contents/Resources/Tools/import-core.py']:
  runtime=root/('cores-'+tool.parent.parent.name);runtime.mkdir()
  args=[sys.executable,tool,'--engine','mgba','--platform','gba','--binary',core,'--root',runtime,'--host',app/'Contents/MacOS/AkitoStation','--upstream','https://github.com/mgba-emu/mgba','--license','MPL-2.0']
  for extra in [[],['--external']]:
   result=run(args+extra);assert result.returncode==0,result.stderr
  before=sha(core);assert before==sha(core)
  result=run([str(x).replace('gba','ps3') if str(x)=='gba' else x for x in args]);assert result.returncode!=0
  results.append(dict(tool='packaged' if tool.is_relative_to(app) else 'source',core_managed_install=True,core_external_registration=True,wrong_console_rejected=True,native_abi_verified=True))
print(json.dumps(results,indent=2))
