"""Offline behavioral tests. Run: python -m unittest discover -s tests -v
Requires lupa (pip install lupa). These mocks do not replace an in-game test.
"""
import base64
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            clock = 0
            os.clock = function() return clock end
            queue = {}
            task = {
                spawn = function(fn) table.insert(queue, fn) end,
                defer = function(fn) table.insert(queue, fn) end,
                wait = function(t) clock = clock + (t or 0.01) end,
            }
            function drain() local jobs=queue; queue={}; for _,fn in ipairs(jobs) do fn() end end
            table.clear = function(t) for k in pairs(t) do t[k]=nil end end
            typeof = type
            warn = function() end
            player = {Name="Tester", UserId=123}
            services = {Players={LocalPlayer=player}, HttpService={}, ReplicatedStorage={}, Workspace={}}
            function services.HttpService:JSONEncode(t) return "json" end
            function services.HttpService:GenerateGUID() return tostring(clock) end
            function services.ReplicatedStorage:FindFirstChild() return nil end
            function services.Workspace:FindFirstChild() return nil end
            game={PlaceId=138271828389486, GameId=1}
            function game:GetService(name) return services[name] end
            CFrame = {new=function(...) return {Position={}, values={...}} end}
        ''')
        self.lua.globals().Core = self.lua.execute((ROOT/'ReAdventuresV2/Core.lua').read_text())

    def test_source_syntax(self):
        for path in list((ROOT/'ReAdventuresV2').glob('*.lua'))+[ROOT/'Loader/Loader.lua']:
            ok, err = self.lua.eval('function(s) local f,e=load(s);return f~=nil,e end')(path.read_text())
            self.assertTrue(ok, str(path)+': '+str(err))


    def test_auto_ready_votes_once_and_waits_for_state(self):
        self.lua.execute('''
            local app=Core.new(); app.running=true
            app.tracker.state.map.isLobby=false
            app.tracker.state.map.mapLoaded=true
            app.tracker.state.match.serverReady=true
            app.tracker.state.match.started=true -- may already be true before the first wave
            app.tracker.state.match.wavesStarted=false
            app.tracker.state.match.finished=false
            app.tracker.state.match.votingFinished=false
            app.tracker.state.match.voteCount=1 -- another player may already be ready
            local calls=0
            app:SetActionAdapter(function(a) assert(a.kind=="ready"); calls=calls+1; return true end)
            app:SetAutoStoryConfig({autoReady=true})
            clock=3
            app:_automationStep(); assert(calls==1 and app.readySubmitted)
            app:_automationStep(); assert(calls==1)
            clock=6
            app.tracker.state.match.voteCount=2
            app:_automationStep(); assert(calls==1)
        ''')

    def test_post_match_exclusivity(self):
        self.lua.execute('''
            local app=Core.new()
            app:SetAutoStoryConfig({autoReplay=true})
            app:SetAutoStoryConfig({autoNext=true})
            assert(app.autoStory.autoNext and not app.autoStory.autoReplay)
            app:SetAutoStoryConfig({autoReturnLobby=true})
            assert(app.autoStory.autoReturnLobby and not app.autoStory.autoNext)
        ''')

    def test_place_only_selected_with_marker_and_budget(self):
        self.lua.execute('''
            local app=Core.new(); app.running=true
            app.tracker.state.match.phase="PLAYING"
            app.tracker.state.player.money=100
            function app:GetEquippedUnits() return {{slot=1,uuid="u1",unitId="a",equipped=true,cost=200}} end
            function app:_matchingModel() return nil end
            local calls=0
            app:SetActionAdapter(function(a) assert(a.kind=="place" and a.unit.uuid=="u1"); calls=calls+1; return true end)
            app:SetAutoStoryConfig({autoPlace=true,placeSlots={1}})
            app:_automationStep(); assert(calls==0)
            app.placementMarkers[1]={cframe={0,0,0}}
            app:_automationStep(); assert(calls==0)
            app.tracker.state.player.money=300
            app:_automationStep(); assert(calls==1)
            app.replay.running=true; app:_automationStep(); assert(calls==1)
            app.replay.running=false; app.recorder.recording=true; app:_automationStep(); assert(calls==1)
        ''')

    def test_post_match_once_and_no_next_on_defeat(self):
        self.lua.execute('''
            local app=Core.new(); app.running=true
            app.tracker.state.match.finished=true
            app.lastWebhookResultKey="result"
            local outcome="defeat"
            function app:_readResult() return {outcome=outcome} end
            local calls=0
            app:SetActionAdapter(function(a) assert(a.kind=="next");calls=calls+1;return true end)
            app:SetAutoStoryConfig({autoNext=true})
            app:_automationStep();assert(calls==0)
            outcome="victory";app:_automationStep();app:_automationStep();assert(calls==1)
        ''')

    def test_replay_failure_propagates(self):
        self.lua.execute('''
            local replay=Core.MacroReplay.new()
            local completed, failure
            replay:start({events={{t=0},{t=1}}},function(event,index,total,finished,err)
                if finished then completed=true;failure=err;return end
                return false,"rejected"
            end)
            drain()
            assert(completed and failure=="rejected")
            assert(not replay.running and replay.currentIndex==1)
        ''')

    def test_cancelled_replay_does_not_finish_new_replay(self):
        self.lua.execute('''
            local replay=Core.MacroReplay.new(); local calls=0
            replay:start({events={{t=0}}},function() calls=calls+1 end)
            replay:stop();drain();assert(calls==0 and not replay.running)
        ''')

    def test_replay_waits_for_confirmed_placement(self):
        self.lua.execute('''
            local app=Core.new();app.running=true;app.replay.running=true
            app.tracker.state.match.phase="PLAYING"
            local placed, calls = false, 0
            function app:_matchingModel() if placed then return {Parent=true} end end
            function app:GetEquippedUnits() return {{slot=1,uuid="new",unitId="a",equipped=true}} end
            app:SetActionAdapter(function(a)
                assert(a.kind=="place" and a.unit.uuid=="new")
                calls=calls+1;placed=true;return true
            end)
            local ok=app:_executeReplay({event={type="PLACE_DETECTED",data={unit={uuid="old",unitId="a",cframe={0,0,0}}}}})
            assert(ok and calls==1 and app.replayUnits.old)
        ''')

    def test_replay_never_sells_removed_units(self):
        self.lua.execute('''
            local app=Core.new()
            app:SetActionAdapter(function() error("must not dispatch") end)
            assert(app:_executeReplay({event={type="UNIT_REMOVED"}}))
        ''')

    def test_endpoint_errors_and_argument_forwarding(self):
        self.lua.execute('''
            local app=Core.new()
            local remote={}
            function remote:IsA(t) return t=="RemoteFunction" end
            function remote:InvokeServer(uuid,cf) assert(uuid=="unit" and cf=="position");return false end
            local root={FindFirstChild=function(_,name) assert(name=="spawn_unit");return remote end}
            local endpoints={FindFirstChild=function(_,name) assert(name=="client_to_server");return root end}
            function services.ReplicatedStorage:FindFirstChild(name) assert(name=="endpoints");return endpoints end
            local ok,err=app:_dispatch({kind="place",unit={uuid="unit"},cframe="position"})
            assert(not ok and err:find("rejected"))
        ''')

    def test_webhook_environment_transport(self):
        self.lua.execute('''
            local app=Core.new(); app.webhook.url="https://example.invalid/webhook"
            request=function(options)
                assert(options.Method=="POST" and options.Body=="json")
                return {StatusCode=204}
            end
            assert(app:_postWebhook({}))
            request=function() return {StatusCode=429} end
            assert(not app:_postWebhook({}))
        ''')

    def test_macro_library_refresh_events(self):
        self.lua.execute('''
            local app=Core.new();local changes=0
            app:On("macrosChanged",function() changes=changes+1 end)
            function app.recorder:stop() return true,{schema="re-adventures-macro",version=2,events={},snapshots={}} end
            local ok,macro,id=app:StopRecording();assert(ok and app:GetSelectedMacroId()==id)
            app:RenameMacro(id,"renamed");app:DeleteMacro(id);drain();assert(changes==3)
        ''')

    def test_loader_matches_sources_and_preserves_other_payloads(self):
        spec=importlib.util.spec_from_file_location('builder',ROOT/'tools/build_loader.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        source=(ROOT/'Loader/Loader.lua').read_text()
        match=module.PATTERN.search(source)
        encoded=''.join(re.findall(r'"([A-Za-z0-9+/=]+)"',match[2]))
        self.assertEqual(module.crypt(base64.b64decode(encoded),int(match[3])),module.payload())
        original=subprocess.check_output(['git','show','HEAD:Loader/Loader.lua'],cwd=ROOT,text=True)
        self.assertEqual(module.PATTERN.sub('PAYLOAD',source),module.PATTERN.sub('PAYLOAD',original))

if __name__=='__main__':unittest.main()
