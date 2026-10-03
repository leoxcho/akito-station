#!/usr/bin/env python3
"""Fail closed on unexpected Public bundle content; no Developer access/mutations."""
import hashlib,json,pathlib,plistlib,re,subprocess,struct
root=pathlib.Path(__file__).resolve().parents[1]
app=root/'Build/Akito Station.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleName']==info['CFBundleDisplayName']=='Akito Station'
assert info['CFBundleIconFile']=='AppIcon'
icon=(app/'Contents/Resources/AppIcon.icns').read_bytes()
assert icon[:4]==b'icns' and icon==(root/'Resources/AppIcon.icns').read_bytes()
assert info['CFBundleIdentifier']=='app.akitostation.public'
assert info['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['akito']
assert info['AKITO_API_BASE_URL']=='https://akito-station-backend.onrender.com'
helper=app/'Contents/Helpers/Akito Station Player.app'
h=plistlib.loads((helper/'Contents/Info.plist').read_bytes())
assert h['CFBundleIdentifier']=='app.akitostation.public.player'
binaries=[app/'Contents/MacOS/AkitoStation',helper/'Contents/MacOS/AkitoStation']
def text_section(path):
 b=path.read_bytes(); offset=32
 for _ in range(struct.unpack_from('<I',b,16)[0]):
  cmd,size=struct.unpack_from('<II',b,offset)
  if cmd==0x19:
   for i in range(struct.unpack_from('<I',b,offset+64)[0]):
    section=offset+72+i*80
    if b[section:section+16].rstrip(bytes([0]))==b'__text':
     length=struct.unpack_from('<Q',b,section+40)[0];start=struct.unpack_from('<I',b,section+48)[0]
     return b[start:start+length]
  offset+=size
 raise AssertionError('Missing Mach-O text section')
assert text_section(binaries[0])==text_section(binaries[1])
for p in binaries:
 b=p.read_bytes()
 for forbidden in [b'--settings-audit',b'Diagnose and repair',b'Add emulator from GitHub',b'AkitoStation/preferences.json',b'/Volumes/',b'/Users/']:
  assert forbidden not in b,(p.name,forbidden)
 for required in [b'app.akitostation.public.session',b'Akito Station PRO Membership',b'AkitoStationPublic/preferences.json']:
  assert required in b,(p.name,required)
 allowed={'AkitoStation','Info.plist','CodeResources','AppIcon.icns','StationLogo.png'}
for p in app.rglob('*'):
 assert not p.is_symlink(),f'Unexpected symlink: {p}'
 if not p.is_file():continue
 assert 'RuntimeSeeds' not in p.parts
 assert p.name in allowed or p.suffix in ['.py','.patch','.json','.md','.txt'],f'Unexpected resource: {p}'
 b=p.read_bytes()
 assert not re.search(rb'(?:sk_live_|sk_test_|whsec_|ghp_|github_pat_|AKIA)[A-Za-z0-9_]{16,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',b),p
 assert b'/Volumes/' not in b and b'/Users/' not in b,p
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('PASS: Public identities, helper code-section equality, Developer tool exclusion, isolated storage, resource allowlist, personal-path/credential-pattern scans, strict signatures')
