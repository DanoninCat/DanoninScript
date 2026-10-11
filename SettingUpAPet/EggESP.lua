return function(ctx)
    local S, LP, RS, Links = ctx.State, ctx.Player, game:GetService("ReplicatedStorage"), ctx.Links
    local EggData = ctx.EggData
    local palette = {
        Common = Color3.fromRGB(210,215,225),
        Rare = Color3.fromRGB(75,175,255),
        Epic = Color3.fromRGB(175,95,255),
        Legendary = Color3.fromRGB(255,194,70),
        Mythic = Color3.fromRGB(255,90,180),
        Divine = Color3.fromRGB(255,236,115),
        Secret = Color3.fromRGB(240,85,85),
        Ethereal = Color3.fromRGB(95,245,225),
    }
    local marked = {}
    local stopped = false

    local function enabled()
        return S.EggsESP or S.ShowEggName or S.ShowEggValue or S.ShowEggDistance
    end
    local function activeEggs()
        local server = RS:FindFirstChild("ServerData")
        return (server and server:FindFirstChild("ActiveEggs"))
            or RS:FindFirstChild("ActiveEggs")
    end
    local function point(root)
        if not root then return nil end
        return root.Position
    end
    local function valueOf(record, config)
        for _,attr in ipairs({"Value","SellPrice"}) do
            local v = tonumber(record:GetAttribute(attr))
            if v then return v end
        end
        local v = type(config)=="table" and tonumber(config.SellPrice)
        return v
    end
    local function create(record)
        local anchor = Instance.new("Part")
        anchor.Name="CAT_EMPIRE_WORLD_EGG_ESP"
        anchor.Anchored=true
        anchor.CanCollide=false
        anchor.CanTouch=false
        anchor.CanQuery=false
        anchor.Size=Vector3.new(0.2,0.2,0.2)
        anchor.Transparency=1
        anchor.Parent=workspace
        local tag=Instance.new("BillboardGui")
        tag.Name="CAT_EMPIRE_EGG_INFORMATION"
        tag.AlwaysOnTop=true
        tag.MaxDistance=0
        tag.Size=UDim2.fromOffset(250,100)
        tag.StudsOffsetWorldSpace=Vector3.new(0,3,0)
        tag.Adornee=anchor
        tag.Parent=anchor
        local label=Instance.new("TextLabel")
        label.Name="Information"
        label.Size=UDim2.fromScale(1,1)
        label.BackgroundTransparency=1
        label.Font=Enum.Font.GothamBold
        label.TextSize=14
        label.TextWrapped=true
        label.TextStrokeColor3=Color3.new(0,0,0)
        label.TextStrokeTransparency=0.15
        label.TextYAlignment=Enum.TextYAlignment.Center
        label.TextColor3=Color3.new(1,1,1)
        label.Parent=tag
        local entry={anchor=anchor,label=label}
        marked[record]=entry
        return entry
    end
    local function remove(record)
        local entry=marked[record]
        if entry then
            pcall(function() entry.anchor:Destroy() end)
            marked[record]=nil
        end
    end
    local function refresh()
        if stopped or not S.Running or not enabled() then
            for record in pairs(marked) do remove(record) end
            return
        end
        local active=activeEggs()
        if not active then
            for record in pairs(marked) do remove(record) end
            return
        end
        local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local seen={}
        local now=workspace:GetServerTimeNow()
        local cycles=ctx.CollectedCycles()
        for _,record in ipairs(active:GetChildren()) do
            local name=record:GetAttribute("Egg")
            local pos=record:GetAttribute("Position")
            local owner=record:GetAttribute("PrivateTo")
            local drop=tonumber(record:GetAttribute("DropEndsAt")) or 0
            if type(name)=="string" and typeof(pos)=="Vector3"
                and (not owner or owner==LP.UserId)
                and drop<=now
                and not ctx.IsClaimed(name,record,cycles) then
                seen[record]=true
                local entry=marked[record]
                if not entry or not entry.anchor.Parent then entry=create(record) end
                entry.anchor.Position=pos+Vector3.new(0,1,0)
                local info=EggData[name]
                local rarity=type(info)=="table" and info.Rarity or record:GetAttribute("Rarity")
                rarity=type(rarity)=="string" and rarity or "Unknown"
                local lines={}
                if S.EggsESP then lines[#lines+1]=rarity end
                if S.ShowEggName then lines[#lines+1]=name end
                if S.ShowEggValue then
                    local worth=valueOf(record,info)
                    lines[#lines+1]=worth and ("Value: $"..tostring(worth)) or "Value: N/A"
                end
                if S.ShowEggDistance and root then
                    lines[#lines+1]=string.format("Distance: %d studs",math.floor((root.Position-pos).Magnitude))
                end
                entry.label.Text=table.concat(lines,"\n")
                entry.label.TextColor3=palette[rarity] or Color3.new(1,1,1)
            end
        end
        for record in pairs(marked) do
            if not seen[record] or not record:IsDescendantOf(active) then remove(record) end
        end
    end
    local function run()
        while S.Running and not stopped do
            local ok,err=pcall(refresh)
            if not ok then S.LastError="Egg ESP: "..tostring(err) end
            task.wait(0.45)
        end
        for record in pairs(marked) do remove(record) end
    end
    task.spawn(run)
    return function()
        stopped=true
        for record in pairs(marked) do remove(record) end
    end
end