return function(ctx)
    local S, LP, Tabs, Links=ctx.State,ctx.Player,ctx.Tabs,ctx.Links
    local RunService=game:GetService("RunService")
    local UIS=game:GetService("UserInputService")
    local Lighting=game:GetService("Lighting")
    local TeleportService=game:GetService("TeleportService")
    local Props={}
    local bodyCollisions={}
    local stopped=false
    S.Fullbright=false
    S.LowGraphics=false
    S.Disable3D=false
    S.LimitFPS=false
    S.MaxFPS=60
    S.WalkSpeedOverride=false
    S.WalkSpeed=16
    S.JumpPowerOverride=false
    S.JumpPower=50
    S.InfiniteJump=false
    S.NoClip=false
    S.Fly=false
    S.FlySpeed=100
    S.JoinJobId=""

    local function set(object,key,v)
        local known=Props[object]
        if not known then known={};Props[object]=known end
        if known[key]==nil then
            local ok,old=pcall(function() return object[key] end)
            if not ok then return end
            known[key]=old
        end
        pcall(function() object[key]=v end)
    end
    local function restore(object,key)
        local known=Props[object]
        if known and known[key]~=nil then
            pcall(function() object[key]=known[key] end)
            known[key]=nil
        end
    end
    local function button(title,fn)
        Tabs.Settings:AddButton({Title=title,Callback=function()
            task.spawn(function()
                local ok,e=pcall(fn)
                if not ok then ctx.Notify(e) end
            end)
        end})
    end
    local function toggle(name,title)
        Tabs.Settings:AddToggle("SUP_OPT_"..name,{
            Title=title,Default=false,
            Callback=function(v) S[name]=v==true end,
        })
    end
    toggle("Fullbright","Fullbright")
    toggle("LowGraphics","Low Graphics")
    toggle("Disable3D","Disable 3D Rendering / Black Screen")
    toggle("LimitFPS","Limit FPS")
    Tabs.Settings:AddSlider("SUP_OPT_FPS",{
        Title="FPS Cap",Min=20,Max=240,Default=60,Rounding=0,
        Callback=function(v) S.MaxFPS=math.floor(v) end,
    })
    toggle("WalkSpeedOverride","Override Walk Speed")
    Tabs.Settings:AddSlider("SUP_OPT_Walk",{
        Title="Walk Speed",Min=16,Max=150,Default=16,Rounding=0,
        Callback=function(v) S.WalkSpeed=v end,
    })
    toggle("JumpPowerOverride","Override Jump Power")
    Tabs.Settings:AddSlider("SUP_OPT_Jump",{
        Title="Jump Power",Min=50,Max=200,Default=50,Rounding=0,
        Callback=function(v) S.JumpPower=v end,
    })
    toggle("InfiniteJump","Infinite Jump")
    toggle("NoClip","NoClip")
    toggle("Fly","Fly")
    Tabs.Settings:AddSlider("SUP_OPT_FlySpeed",{
        Title="Fly Speed",Min=20,Max=300,Default=100,Rounding=0,
        Callback=function(v) S.FlySpeed=v end,
    })
    button("Rejoin Current Server",function()
        TeleportService:Teleport(game.PlaceId,LP)
    end)
    Tabs.Settings:AddInput("SUP_OPT_JobId",{
        Title="Server JobId",Default="",Placeholder="Job ID",
        Callback=function(v) S.JoinJobId=tostring(v or "") end,
    })
    button("Join JobId",function()
        if S.JoinJobId~="" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId,S.JoinJobId,LP)
        end
    end)
    button("Copy JobId",function()
        if type(setclipboard)=="function" then setclipboard(game.JobId) end
    end)

    Links[#Links+1]=UIS.JumpRequest:Connect(function()
        if S.InfiniteJump then
            local _,hum=ctx.GetRoot()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
    local previous3D,previousFPS
    local accumulator=0
    Links[#Links+1]=RunService.Heartbeat:Connect(function(dt)
        if not S.Running or stopped then return end
        accumulator=accumulator+dt
        if S.Fly and not S.AutoCollectEggs and not S.AutoCollectCandy then
            local root,hum=ctx.GetRoot()
            local camera=workspace.CurrentCamera
            if root and hum and camera then
                local direction=Vector3.zero
                local look=camera.CFrame.LookVector
                local right=camera.CFrame.RightVector
                if UIS:IsKeyDown(Enum.KeyCode.W) then direction=direction+look end
                if UIS:IsKeyDown(Enum.KeyCode.S) then direction=direction-look end
                if UIS:IsKeyDown(Enum.KeyCode.A) then direction=direction-right end
                if UIS:IsKeyDown(Enum.KeyCode.D) then direction=direction+right end
                if UIS:IsKeyDown(Enum.KeyCode.Space) then direction=direction+Vector3.yAxis end
                if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then direction=direction-Vector3.yAxis end
                root.AssemblyLinearVelocity=direction.Magnitude>0
                    and direction.Unit*S.FlySpeed or Vector3.zero
                if hum:GetState()~=Enum.HumanoidStateType.Physics then
                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                end
            end
        end
        if S.NoClip then
            local character=LP.Character
            if character then
                for _,part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        if bodyCollisions[part]==nil then bodyCollisions[part]=true end
                        part.CanCollide=false
                    end
                end
            end
        elseif next(bodyCollisions) then
            for part in pairs(bodyCollisions) do
                pcall(function() part.CanCollide=true end)
                bodyCollisions[part]=nil
            end
        end
        if accumulator<.6 then return end
        accumulator=0
        local _,hum=ctx.GetRoot()
        if hum and LP:GetAttribute("IsRiding")~=true then
            if S.WalkSpeedOverride then hum.WalkSpeed=S.WalkSpeed end
            if S.JumpPowerOverride then hum.JumpPower=S.JumpPower end
        end
        if S.Fullbright then
            set(Lighting,"Brightness",3)
            set(Lighting,"GlobalShadows",false)
            set(Lighting,"Ambient",Color3.fromRGB(255,255,255))
            set(Lighting,"OutdoorAmbient",Color3.fromRGB(200,200,200))
        else
            for _,k in ipairs({"Brightness","GlobalShadows","Ambient","OutdoorAmbient"}) do
                restore(Lighting,k)
            end
        end
        local terrain=workspace:FindFirstChildOfClass("Terrain")
        if S.LowGraphics and terrain then
            set(terrain,"WaterWaveSize",0)
            set(terrain,"WaterWaveSpeed",0)
            set(terrain,"WaterReflectance",0)
            set(terrain,"WaterTransparency",1)
        elseif terrain then
            for _,k in ipairs({"WaterWaveSize","WaterWaveSpeed","WaterReflectance","WaterTransparency"}) do
                restore(terrain,k)
            end
        end
        if S.Disable3D~=previous3D then
            previous3D=S.Disable3D
            pcall(function() RunService:Set3dRenderingEnabled(not previous3D) end)
        end
        if type(setfpscap)=="function" then
            local desired=S.LimitFPS and S.MaxFPS or 0
            if desired~=previousFPS then
                previousFPS=desired
                pcall(setfpscap,desired>0 and desired or 240)
            end
        end
    end)
    for _,key in ipairs({
        "Fullbright","LowGraphics","Disable3D","LimitFPS",
        "WalkSpeedOverride","JumpPowerOverride","InfiniteJump","NoClip","Fly",
    }) do ctx.ConfigKeys[#ctx.ConfigKeys+1]=key end

    return function()
        stopped=true
        for obj,props in pairs(Props) do
            for key in pairs(props) do restore(obj,key) end
        end
        for part in pairs(bodyCollisions) do
            pcall(function() part.CanCollide=true end)
        end
        pcall(function() RunService:Set3dRenderingEnabled(true) end)
    end
end