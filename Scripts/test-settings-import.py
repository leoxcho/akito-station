#!/usr/bin/env python3
import importlib.util,pathlib,tempfile,unittest
spec=importlib.util.spec_from_file_location('importer',pathlib.Path(__file__).with_name('import-emulator-settings.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ImportTests(unittest.TestCase):
 def test_dolphin_reimport_updates_core_and_copies_wii_overrides(self):
  with tempfile.TemporaryDirectory() as t:
   root=pathlib.Path(t);home=root/'home';saves=root/'saves';source=home/'Library/Application Support/Dolphin';config=source/'Config';config.mkdir(parents=True)
   original='[Core]\nGFXBackend = Vulkan\nSIDevice0 = 6\nNANDRootPath = /original/nand\n[SDL_Hints]\nSDL_JOYSTICK_HIDAPI_PS5_PLAYER_LED = 0\n[DSP]\nVolume = 73\n'
   (config/'Dolphin.ini').write_text(original)
   (config/'WiimoteNew.ini').write_text('[Wiimote1]\nExtension = Classic\n')
   (source/'GameSettings').mkdir();(source/'GameSettings/RTEST.ini').write_text('[Controls]\nWiimoteProfile1 = Classic\n')
   dest=saves/'Systems/dolphin/Dolphin';(dest/'Config').mkdir(parents=True)
   (dest/'Config/Dolphin.ini').write_text('[Core]\nGFXBackend = Metal\nSIDevice0 = 0\n')
   module.import_settings('dolphin',saves,home)
   text=(dest/'Config/Dolphin.ini').read_text()
   self.assertIn('GFXBackend = Vulkan',text);self.assertIn('SIDevice0 = 6',text);self.assertIn('[SDL_Hints]',text);self.assertIn('Volume = 73',text);self.assertNotIn('NANDRootPath',text)
   self.assertEqual((source/'GameSettings/RTEST.ini').read_bytes(),(dest/'GameSettings/RTEST.ini').read_bytes())
   self.assertEqual((config/'Dolphin.ini').read_text(),original)
   self.assertTrue(list((dest/'Config').glob('*.before-settings-import-*')))
if __name__=='__main__':unittest.main()
