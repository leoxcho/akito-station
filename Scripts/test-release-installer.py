#!/usr/bin/env python3
"""Exercise package staging without downloading or launching an emulator."""
import importlib.util,json,pathlib,plistlib,subprocess,sys,tempfile,zipfile
scripts=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('installer',scripts/'install-release.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for path in ['../escape','/absolute','a/../../escape','a\\escape']:
 try:module.safe_member(path)
 except ValueError:pass
 else:raise AssertionError('Accepted unsafe archive member')
with tempfile.TemporaryDirectory(prefix='arm-release-test-') as temporary:
 root=pathlib.Path(temporary);app=root/'Fixture.app';contents=app/'Contents';binary=contents/'MacOS/fixture';binary.parent.mkdir(parents=True)
 (contents/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='fixture',CFBundleIdentifier='app.akitostation.updatefixture',CFBundleShortVersionString='1')))
 source=root/'fixture.c';source.write_text('int main(void){return 0;}')
 subprocess.run(['xcrun','clang','-arch','arm64',str(source),'-o',str(binary)],check=True)
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
 archive=root/'release.zip';subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(app),str(archive)],check=True)
 runtimes=root/'runtimes';parent=runtimes/'rpcs3';parent.mkdir(parents=True);selection=parent/'selection.json';selection.write_text('{"current":"previous-good"}')
 result=root/'result.json'
 command=[sys.executable,str(scripts/'install-release.py'),'--archive',str(archive),'--engine','rpcs3','--root',str(runtimes),'--repository','https://github.com/example/emulator','--release','v1','--result-file',str(result)]
 subprocess.run(command,check=True)
 manifest=json.loads(result.read_text());assert manifest['id']=='rpcs3' and manifest['revision']=='v1' and manifest['architecture']=='arm64'
 assert 'gameUntested' in manifest['capabilities'];assert json.loads(selection.read_text())['current']=='previous-good'
 # Corrupt signed code. It must not be silently re-signed and installed.
 with binary.open('ab') as f:f.write(b'corrupt signature')
 bad=root/'bad.zip';subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(app),str(bad)],check=True)
 command[command.index('--archive')+1]=str(bad)
 assert subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
 assert json.loads(selection.read_text())['current']=='previous-good'
 escape=app/'escape';escape.symlink_to('/tmp')
 try:module.validate_bundle(app)
 except ValueError:pass
 else:raise AssertionError('Accepted escaping bundle symlink')
print('Release staging, signature rejection, archive paths and selection preservation passed')
