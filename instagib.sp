#include <sourcemod>
#include <sdktools>

#include <tf2>
#include <tf2_stocks>

#include <sdkhooks>
#include <tf2items>

#pragma semicolon 1

#define PLUGIN_VERSION "0.1.0"
#define PLUGIN_PREFIX "[IG]"
#define PLUGIN_TAG "instagib"
#define PLUGIN_HOSTNAME "%s | Instagib"

// squared max distance to walls for instajumps
#define MAX_INSTAJUMP_DISTANCE (192.0 * 192.0)

// Variables {{{
public Plugin:myinfo = {
    name = "Instagib",
    author = "mphe",
    description = "Same class, same speed, railguns, instant kills",
    version = PLUGIN_VERSION,
    url = ""
};


new Handle:railgunConfig = INVALID_HANDLE;

new Handle:cvarEnabled      = INVALID_HANDLE;
new Handle:cvarFalldamage   = INVALID_HANDLE;
new Handle:cvarNoDoubleJump = INVALID_HANDLE;
new Handle:cvarJumpScale    = INVALID_HANDLE;

new bool:gEnabled = false;
new Float:gJumpScale = 600.0;
// new gViewModel;

// Game vars
new Handle:cvarAirDashCount = INVALID_HANDLE;
new Handle:cvarCrits        = INVALID_HANDLE;
new Handle:cvarTags         = INVALID_HANDLE;
new Handle:cvarHostname     = INVALID_HANDLE;

new String:sv_tags[255];
new String:hostname[255];
new tf_scout_air_dash_count;
new tf_weapon_criticals;

// }}}


// Plugin initialization {{{
public OnPluginStart()
{
    SetupRailgun();

    CreateConVar("instagib_version", PLUGIN_VERSION, "Instagib version", FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
    cvarEnabled      = CreateConVar("ig_enabled",            "0", "Enable/Disable Instagib.");
    cvarFalldamage   = CreateConVar("ig_falldamage",         "0", "Enable/Disable falldamage.");
    cvarJumpScale    = CreateConVar("ig_instajump_scale",  "600", "Instajump strength. 0 to disable instajumps.");
    cvarNoDoubleJump = CreateConVar("ig_disable_doublejump", "0", "Disable scout doublejumps.");

    cvarAirDashCount = FindConVar("tf_scout_air_dash_count");
    cvarCrits        = FindConVar("tf_weapon_criticals");
    cvarTags         = FindConVar("sv_tags");
    cvarHostname     = FindConVar("hostname");

    HookConVarChange(cvarEnabled,   ChangeEnabled);
    HookConVarChange(cvarJumpScale, ChangeJumpScale);

    // Trigger convar updates
    ChangeEnabled  (cvarEnabled, "", "");
    ChangeJumpScale(cvarJumpScale, "", "");
}
// }}}

// Change Hooks {{{
public ChangeEnabled(Handle:convar, const String:oldValue[], const String:newValue[])
{
    new bool:enabled = GetConVarBool(convar);
    if (enabled != gEnabled)
    {
        gEnabled = enabled;

        if (gEnabled)
            InitInstagib();
        else
            DeinitInstagib();
    }
}

public ChangeJumpScale(Handle:convar, const String:oldValue[], const String:newValue[])
{
    gJumpScale = GetConVarFloat(convar);
}
// }}}

// Events {{{
public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponName[], &bool:result)
{
    if (!gEnabled)
        return;

    // infinite ammo
    SetEntProp(weapon, Prop_Data, "m_iClip1", 100);

    if (gJumpScale != 0.0)
    {
        decl Float:origin[3], Float:dir[3];

        GetClientEyePosition(client, origin);
        GetClientEyeAngles(client, dir);

        TR_TraceRayFilter(origin, dir, MASK_SHOT_HULL, RayType_Infinite,
                TR_FilterSelf, client);

        if (TR_DidHit(INVALID_HANDLE))
        {
            decl Float:end[3], Float:vel[3], Float:delta[3];

            TR_GetEndPosition(end, INVALID_HANDLE);
            GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
            SubtractVectors(origin, end, delta);

            new Float:sqd = GetVectorDotProduct(delta, delta);

            if (sqd <= MAX_INSTAJUMP_DISTANCE)
            {
                NormalizeVector(delta, delta);
                ScaleVector(delta, (1 - sqd / MAX_INSTAJUMP_DISTANCE) * gJumpScale);
                AddVectors(delta, vel, vel);
                TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
            }
        }
    }
}

public OnEntityCreated(ent, const String:classname[])
{
    // Disable regeneration
    if (StrEqual(classname, "func_regenerate"))
        SDKHook(ent, SDKHook_Spawn, OnRegenSpawned);
}

public OnRegenSpawned(ent)
{
    AcceptEntityInput(ent, "Disable");
}

public Action:OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    SetupPlayer(client);
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damageType)
{
    if (damageType & DMG_FALL && !GetConVarBool(cvarFalldamage))
        return Plugin_Stop;
    return Plugin_Continue;
}

public OnClientPutInServer(client)
{
    if (gEnabled && !IsFakeClient(client))
        SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}
// }}}

// Plugin Logic {{{
InitInstagib()
{
    { // set tag and hostname
        GetConVarString(cvarTags, sv_tags, sizeof(sv_tags));
        new String:newtags[255];
        Format(newtags, sizeof(newtags), "%s,%s", sv_tags, PLUGIN_TAG);
        SetConVarString(cvarTags, newtags);

        GetConVarString(cvarHostname, hostname, sizeof(hostname));
        new String:newhostname[255];
        Format(newhostname, sizeof(newhostname), PLUGIN_HOSTNAME, hostname);
        SetConVarString(cvarHostname, newhostname);
    }

    { // change game vars
        if (GetConVarBool(cvarNoDoubleJump))
        {
            tf_scout_air_dash_count = GetConVarInt(cvarAirDashCount);
            SetConVarInt(cvarAirDashCount, 0, true, true);
        }

        tf_weapon_criticals = GetConVarInt(cvarCrits);
        SetConVarInt(cvarCrits, 0, true, true);
    }

    HookEvent("player_spawn", OnPlayerSpawn);
    HookEvent("player_team", OnPlayerSpawn);
    HookEvent("post_inventory_application", OnPlayerSpawn);

    for (new i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            OnClientPutInServer(i);
            SetupPlayer(i);
        }

    PrintToChatAll("%s Instagib enabled", PLUGIN_PREFIX);
    PrintToServer("%s Instagib enabled", PLUGIN_PREFIX);
}

DeinitInstagib()
{
    // reset tags and hostname
    SetConVarString(cvarTags, sv_tags);
    SetConVarString(cvarHostname, hostname);

    { // reset game vars
        if (GetConVarBool(cvarNoDoubleJump))
            SetConVarInt(cvarAirDashCount, tf_scout_air_dash_count, true, true);

        SetConVarInt(cvarCrits, tf_weapon_criticals, true, true);
    }

    UnhookEvent("player_spawn", OnPlayerSpawn);
    UnhookEvent("player_team", OnPlayerSpawn);
    UnhookEvent("post_inventory_application", OnPlayerSpawn);

    for (new i = 1; i <= MaxClients; i++)
        if (!IsFakeClient(i))
        {
            SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage);
            if (IsClientInGame(i))
                TF2_RegeneratePlayer(i);
        }

    PrintToChatAll("%s Instagib disabled", PLUGIN_PREFIX);
    PrintToServer("%s Instagib disabled", PLUGIN_PREFIX);
}

SetupPlayer(client)
{
    if (IsFakeClient(client) || !IsClientInGame(client))
        return;

    TF2_SetPlayerClass(client, TFClass_Soldier);
    TF2_RemoveAllWeapons(client);

    new railgun = TF2Items_GiveNamedItem(client, railgunConfig);
    SetEntProp(railgun, Prop_Data, "m_iClip1", 99);
    // SetEntData(railgun, FindSendPropInfo("CBaseCombatWeapon", "m_iWorldModelIndex"), gViewModel, 4, true);
    // SetEntData(railgun, FindSendPropInfo("CBaseEntity", "m_nModelIndex"), gViewModel, 4, true);
    EquipPlayerWeapon(client, railgun);
}

SetupRailgun()
{
    if (railgunConfig != INVALID_HANDLE)
        return;

    railgunConfig = TF2Items_CreateItem(OVERRIDE_ALL);
    TF2Items_SetClassname(railgunConfig, "tf_weapon_sniperrifle");
    TF2Items_SetItemIndex(railgunConfig, 526);

    TF2Items_SetLevel(railgunConfig, 1);
    TF2Items_SetQuality(railgunConfig, 1);

    TF2Items_SetNumAttributes(railgunConfig, 6);
    TF2Items_SetAttribute(railgunConfig, 0, 42, 1.0);  // No headshots
    TF2Items_SetAttribute(railgunConfig, 1, 41, 0.0);  // +%s1% charge rate
    TF2Items_SetAttribute(railgunConfig, 2, 305, 1.0); // Fires tracer rounds
    TF2Items_SetAttribute(railgunConfig, 3, 266, 1.0); // Projectiles penetrate enemy players
    TF2Items_SetAttribute(railgunConfig, 4, 2, 200.0); // Damage bonus
    TF2Items_SetAttribute(railgunConfig, 5, 107, 1.7); // +%s1% faster move speed on wearer
}

public bool:TR_FilterSelf(ent, mask, any:data)
{
    return ent != data;
}

// }}}

// {{{
// public OnMapStart()
// {
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_back_blue.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_back.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_back.vtf");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_front_mask.vtf");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_front.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_front.vtf");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_glow_blue.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_glow.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3_glow.vtf");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3.vmt");
//     AddFileToDownloadsTable("materials/models/hideous/railgun/railgun_q3.vtf");
//
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.dx80.vtx");
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.dx90.vtx");
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.mdl");
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.phy");
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.sw.vtx");
//     AddFileToDownloadsTable("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.vvd");
//
//     AddFileToDownloadsTable("sound/weapons/sniper_railgun_single_01.wav");
//     AddFileToDownloadsTable("sound/weapons/sniper_railgun_single_02.wav");
//
//     gViewModel = PrecacheModel("models/weapons/c_models/c_dex_sniperrifle/c_dex_sniperrifle.mdl");
//     PrecacheSound("sound/weapons/sniper_railgun_single_01.wav");
//     PrecacheSound("sound/weapons/sniper_railgun_single_02.wav");
// }
// }}}

// vim: foldmethod=marker
