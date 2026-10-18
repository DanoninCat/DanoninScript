"""Isolated regression tests for Roblox place 99881468171809 only."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
MAIN=(ROOT/"StealABrainrot/Main.lua").read_text(encoding="utf-8")
SETTINGS=(ROOT/"StealABrainrot/Settings.lua").read_text(encoding="utf-8")
LOADER=(ROOT/"Loader/Loader.lua").read_text(encoding="utf-8")

class Game99881468171809Tests(unittest.TestCase):
    def test_routing_only_target(self):
        self.assertIn("if game.PlaceId == 99881468171809 then",LOADER)
        self.assertIn("if game.PlaceId ~= 99881468171809 then",MAIN)
        self.assertIn('StealABrainrot/Main.lua',LOADER)
    def test_dynamic_name_roblox(self):
        self.assertIn('MarketplaceService:GetProductInfo(game.PlaceId)',MAIN)
        self.assertIn('SubTitle = GameTitle',MAIN)
        self.assertIn('Title = GameTitle',MAIN)
        self.assertIn('Status:SetTitle(GameTitle)',MAIN)
        self.assertNotIn('SubTitle = "Steal A Brainrot"',MAIN)
        self.assertNotIn('Status:SetTitle("Steal A Brainrot")',MAIN)
    def test_original_ui_settings_misc(self):
        self.assertEqual(MAIN.count('Fluent:CreateWindow('),1)
        self.assertIn('Settings = Window:AddTab(',MAIN)
        self.assertIn('Misc = Window:AddTab(',MAIN)
        self.assertIn('return function(ctx)',SETTINGS)
        self.assertIn('MarketplaceService:GetProductInfo(game.PlaceId)',SETTINGS)
        for label in ('Auto Rejoin','Anti AFK','Themes','Profiles','Boost FPS','Account','Community'):
            self.assertIn(label,SETTINGS)
    def test_existing_routes_preserved(self):
        for place in ('114326934417838','124216119978534'):
            self.assertIn(place,LOADER)
    def test_lua_syntax_when_lupa_available(self):
        try:
            from lupa import LuaRuntime
        except ImportError:
            self.skipTest("lupa unavailable")
        lua=LuaRuntime(unpack_returned_tuples=True)
        check=lua.eval('function(s) local fn,err=load(s); return fn~=nil,err end')
        for path in (ROOT/"StealABrainrot/Main.lua",ROOT/"StealABrainrot/Settings.lua",ROOT/"Loader/Loader.lua"):
            ok,err=check(path.read_text(encoding="utf-8"))
            self.assertTrue(ok, str(path)+": "+str(err))

if __name__=="__main__":
    unittest.main()
