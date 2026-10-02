#!/usr/bin/env python3
"""Copy graphics/controller configuration into managed storage. Originals are read-only.
Only configuration sections are imported; saves, credentials and firmware are not imported here.
"""
import argparse,configparser,copy,datetime,json,pathlib,re,shutil,xml.etree.ElementTree as ET

MANAGED_ROOT=None

def read(path):return path.read_text(encoding='utf-8-sig') if path.exists() else ''
def write(path,text):
 if MANAGED_ROOT is not None and not path.resolve().is_relative_to(MANAGED_ROOT):raise ValueError("Settings destination escapes managed storage")
 path.parent.mkdir(parents=True,exist_ok=True)
 if path.exists() and path.read_text()==text:return
 if path.exists():
  backup=path.with_name(path.name+'.before-settings-import-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
  shutil.copy2(path,backup)
 path.write_text(text)
def blocks(text):
 parts=re.split(r'(?m)^(\[[^\n]+\])\s*\n',text);return {parts[i][1:-1]:parts[i+1] for i in range(1,len(parts),2)}
def merge_ini(src,dst,allow):
 if not src.exists():return False
 original=read(dst);incoming=blocks(read(src));selected={k:v for k,v in incoming.items() if allow(k)}
 for name,value in selected.items():
  pattern=r'(?ms)^\['+re.escape(name)+r'\][^\n]*\n.*?(?=^\[|\Z)'
  section='['+name+']\n'+value.rstrip()+'\n\n'
  original=re.sub(pattern,lambda _:section,original) if re.search(pattern,original) else original.rstrip()+'\n\n'+section
 if selected:write(dst,original.lstrip('\n'))
 return bool(selected)
def yaml_blocks(text):
 matches=list(re.finditer(r'(?m)^([^\s#][^:\n]*):',text));return {m.group(1):text[m.start():matches[i+1].start() if i+1<len(matches) else len(text)].replace('\n...','') for i,m in enumerate(matches)}
def merge_yaml(src,dst,allow):
 if not src.exists():return False
 original=yaml_blocks(read(dst));incoming=yaml_blocks(read(src));selected={k:v for k,v in incoming.items() if allow(k)};original.update(selected)
 if selected:write(dst,''.join(v.rstrip()+'\n' for v in original.values()))
 return bool(selected)
def tree(src,dst,extensions):
 count=0
 if src.is_dir():
  for file in src.rglob('*'):
   if file.is_symlink() or not file.is_file() or file.suffix not in extensions or file.stat().st_size>4*1024*1024:continue
   write(dst/file.relative_to(src),file.read_text());count+=1
 return count

def ensure_ini(path,section,key,value):
 text=read(path);parts=blocks(text);body=parts.get(section,'')
 if re.search(r'(?m)^'+re.escape(key)+r'\s*=',body):return
 if section in parts:text=re.sub(r'(?m)^\['+re.escape(section)+r'\]\s*$',lambda m:m.group(0)+'\n'+key+' = '+value,text,count=1)
 else:text+='\n['+section+']\n'+key+' = '+value+'\n'
 write(path,text)

def import_settings(engine,saves,home):
 support=home/'Library/Application Support';data=saves/'Systems'/engine;result=[]
 def ini(source,target,allow):
  if merge_ini(source,data/target,allow):result.append(target)
 def yaml(source,target,allow):
  if merge_yaml(source,data/target,allow):result.append(target)
 if engine=='ppsspp_sdl':
  source=home/'.config/ppsspp/PSP/SYSTEM';base='home/.config/ppsspp/PSP/SYSTEM'
  ini(source/'ppsspp.ini',base+'/ppsspp.ini',lambda k:k in ['Graphics','Control','SystemParam'] or k.startswith(('DisplayLayout','TouchControls')))
  ini(source/'controls.ini',base+'/controls.ini',lambda k:True)
 elif engine=='duckstation':
  base='home/Library/Application Support/DuckStation';ini(support/'DuckStation/settings.ini',base+'/settings.ini',lambda k:k in ['GPU','Display','ControllerPorts','InputSources','Hotkeys','TextureReplacements','PostProcessing'] or k.startswith(('Pad','PostProcessing/')))
  file=data/base/'settings.ini';text=read(file)
  if '[Main]' not in text:text+='\n[Main]\nSettingsVersion = 3\nSetupWizardIncomplete = false\nConfirmPowerOff = false\n'
  if '[BIOS]' not in text:text+='\n[BIOS]\nSearchDirectory = bios\n'
  if '[MemoryCards]' not in text:text+='\n[MemoryCards]\nDirectory = memcards\n'
  write(file,text)
  tree(support/'DuckStation/inputprofiles',data/base/'inputprofiles',{'.ini'})
 elif engine=='dolphin':
  for name in ['GFX.ini','GCPadNew.ini','WiimoteNew.ini','FreeLook.ini','FreeLookController.ini','GCKeyNew.ini','DSUClient.ini']:
   ini(support/'Dolphin/Config'/name,'Dolphin/Config/'+name,lambda k:True)
  ini(support/'Dolphin/Config/Dolphin.ini','Dolphin/Config/Dolphin.ini',lambda k:k in ['Display','Input','Controls','SDL_Hints','DSP','BluetoothPassthrough'])
  # These controller-device and backend keys live alongside storage paths in Core.
  source=blocks(read(support/'Dolphin/Config/Dolphin.ini'));file=data/'Dolphin/Config/Dolphin.ini';text=read(file)
  core='\n'.join(l for l in source.get('Core','').splitlines() if re.match(r'(SIDevice\d|GFXBackend)\s*=',l))
  if core:
   for line in core.splitlines():
    key,value=line.split('=',1);key=key.strip();value=value.strip()
    parts=blocks(text);body=parts.get('Core','')
    pattern=r'(?m)^'+re.escape(key)+r'\s*=.*$'
    body=re.sub(pattern,lambda _:key+' = '+value,body) if re.search(pattern,body) else body.rstrip()+'\n'+key+' = '+value+'\n'
    section='[Core]\n'+body.strip()+'\n\n'
    text=re.sub(r'(?ms)^\[Core\][^\n]*\n.*?(?=^\[|\Z)',lambda _:section,text) if 'Core' in parts else text.rstrip()+'\n\n'+section
   write(file,text)
  tree(support/'Dolphin/Config/Profiles',data/'Dolphin/Config/Profiles',{'.ini'})
  tree(support/'Dolphin/GameSettings',data/'Dolphin/GameSettings',{'.ini'})
 elif engine in ('armsx2','pcsx2'):ini(support/('PCSX2' if engine=='pcsx2' else 'ARMSX2')/'inis/PCSX2.ini','inis/PCSX2.ini',lambda k:k=='EmuCore/GS' or k in ['InputSources','Hotkeys'] or k.startswith(('Pad','InputProfile')))
 elif engine=='rpcs3':
  base='home/Library/Application Support/rpcs3';yaml(support/'rpcs3/config.yml',base+'/config.yml',lambda k:k in ['Video','Input/Output'])
  tree(support/'rpcs3/input_configs',data/base/'input_configs',{'.yml'})
 elif engine=='vita3k':
  graphics={'backend-renderer','custom-driver-name','gpu-idx','high-accuracy','resolution-multiplier','disable-surface-sync','screen-filter','v-sync','anisotropic-filtering','texture-cache','async-pipeline-compilation','show-compile-shaders','hashless-texture-cache','import-textures','export-textures','export-as-png','stretch_the_display_area','fullscreen_hd_res_pixel_perfect','boot-apps-full-screen','disable-motion','shader-cache','spirv-shader','fps-hack','pstv-mode','sys-button'}
  yaml(support/'Vita3K/Vita3K/config.yml','config.yml',lambda k:k in graphics or k.startswith(('keyboard-','controller-','performance-overlay')))
 elif engine=='ryujinx':
  source=support/'Ryujinx/Config.json';target=data/'Config.json'
  if source.exists():
   incoming=json.loads(read(source));old=json.loads(read(target) or '{}')
   keys={'backend_threading','res_scale','res_scale_custom','max_anisotropy','aspect_ratio','anti_aliasing','scaling_filter','scaling_filter_level','enable_hardware_acceleration','enable_vsync','vsync_mode','enable_custom_vsync_interval','custom_vsync_interval','enable_shader_cache','enable_texture_recompression','enable_color_space_passthrough','start_fullscreen','enable_keyboard','enable_mouse','disable_input_when_out_of_focus','hotkeys','input_config','graphics_backend','preferred_gpu','use_input_global_config','docked_mode'}
   old.update({k:v for k,v in incoming.items() if k in keys});write(target,json.dumps(old,indent=2)+'\n');result.append('Config.json')
 elif engine=='lime3ds':ini(support/'Lime3DS/config/qt-config.ini','home/Library/Application Support/Lime3DS/config/qt-config.ini',lambda k:k in ['Renderer','Layout','Controls','Shortcuts','MotionTouch'])
 elif engine=='shadps4':
  ini(support/'shadPS4/config.toml','home/Library/Application Support/shadPS4/config.toml',lambda k:k in ['GPU','Vulkan','Input','Bindings'])
  tree(support/'shadPS4/input_config',data/'home/Library/Application Support/shadPS4/input_config',{'.ini','.toml'})
 elif engine=='cemu':
  base='home/Library/Application Support/Cemu';source=support/'Cemu/settings.xml';target=data/base/'settings.xml'
  if source.exists():
   incoming=ET.fromstring(read(source));old=ET.fromstring(read(target) or '<content/>')
   for tag in ['Graphic','GraphicPack','Input','fullscreen']:
    node=incoming.find(tag)
    if node is not None:
     for child in old.findall(tag):old.remove(child)
     old.append(copy.deepcopy(node))
   write(target,ET.tostring(old,encoding='unicode'));result.append(base+'/settings.xml')
  tree(support/'Cemu/controllerProfiles',data/base/'controllerProfiles',{'.xml'})
 elif engine=='xemu':ini(support/'xemu/xemu/xemu.toml','xemu.toml',lambda k:k.startswith(('display','input')))
 elif engine=='xenia':
  # The imported runtime's existing TOML is the authoritative configuration.
  if (data/'xenia-edge.config.toml').exists():result.append('xenia-edge.config.toml (retained)')
 if engine=='dolphin':
  ensure_ini(data/'Dolphin/Config/GFX.ini','Settings','InternalResolution','1')
  ensure_ini(data/'Dolphin/Config/GFX.ini','Hardware','VSync','False')
  ensure_ini(data/'Dolphin/Config/Dolphin.ini','Core','GFXBackend','Metal')
 if engine=='xemu':
  ensure_ini(data/'xemu.toml','display.quality','surface_scale','1')
  ensure_ini(data/'xemu.toml','display.window','vsync','true')
 return result

def main():
 global MANAGED_ROOT
 p=argparse.ArgumentParser();p.add_argument('--saves',type=pathlib.Path,required=True);p.add_argument('--engine',default='all');p.add_argument('--source-home',type=pathlib.Path,default=pathlib.Path.home());p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
 MANAGED_ROOT=a.saves.resolve()
 engines=['ppsspp_sdl','duckstation','dolphin','armsx2','pcsx2','rpcs3','vita3k','ryujinx','lime3ds','shadps4','cemu','xemu','xenia'] if a.engine=='all' else [a.engine]
 report={e:import_settings(e,a.saves,a.source_home) for e in engines}
 text=json.dumps(report,indent=2);print(text)
 if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(text+'\n')
if __name__=='__main__':main()
