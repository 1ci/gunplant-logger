#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
//#include <lastrequest>

#define PLUGIN_VERSION	"2.00"

// Used for admin logs
#define ADMIN_FLAG		Admin_Generic

// Gunplant check duration (in seconds)
#define TIME_INTERVAL	5

new bool:bLateLoad = false;

new g_RoundTime;
new g_FreezeTime;

new Handle:g_Cvar_RoundTime = INVALID_HANDLE;
new Handle:g_Cvar_FreezeTime = INVALID_HANDLE;

new Float:g_fGameTime;

enum Weapon
{
	String:CTName[32],
	CTUserID,
	Time,
	Handle:WeaponTimer
}

new g_Weapon[2048][Weapon];

new g_bCTKilled[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "Gunplant Logger",
	author = "ici",
	version = PLUGIN_VERSION
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	bLateLoad = late;
	return APLRes_Success;
}

public OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	g_Cvar_RoundTime = FindConVar("mp_roundtime");
	g_Cvar_FreezeTime = FindConVar("mp_freezetime");
	
	if (g_Cvar_RoundTime == INVALID_HANDLE)
		LogError("[Gunplant Logger] Could not find \'mp_roundtime\'!");
	
	if (g_Cvar_FreezeTime == INVALID_HANDLE)
		LogError("[Gunplant Logger] Could not find \'mp_freezetime\'!");
	
	if (bLateLoad)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public OnConfigsExecuted()
{
	g_RoundTime = GetConVarInt(g_Cvar_RoundTime);
	g_FreezeTime = GetConVarInt(g_Cvar_FreezeTime);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponDropPost, Hook_WeaponDropPost);
	SDKHook(client, SDKHook_WeaponEquipPost, Hook_WeaponEquipPost);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_fGameTime = GetGameTime(); // Time since round start.
	OnConfigsExecuted();
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (g_bCTKilled[client])
	{
		g_bCTKilled[client] = false;
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (!victim || !IsClientInGame(victim) || GetClientTeam(victim) != 3)
		return;
	
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (attacker < 1 || attacker > MaxClients)
		return;
	
	if (victim != attacker)
	{
		g_bCTKilled[victim] = true;
	}
}

public Hook_WeaponDropPost(client, weapon)
{
	if (!IsValidClient(client) || !IsValidEdict(weapon) || GetClientTeam(client) != 3)
		return;
	
	/*
	if (IsClientInLastRequest(client) > 0)
		return;
	*/
	
	decl String:sWeaponName[64];
	GetEdictClassname(weapon, sWeaponName, sizeof(sWeaponName));
	
	if (!IsWeaponOK(sWeaponName))
		return;
	
	if (g_Weapon[weapon][WeaponTimer] == INVALID_HANDLE)
	{
		GetClientName(client, g_Weapon[weapon][CTName], 32);
		g_Weapon[weapon][CTUserID] = GetClientUserId(client);
		g_Weapon[weapon][Time] = TIME_INTERVAL;
		
		new Handle:hDataPack;
		g_Weapon[weapon][WeaponTimer] = CreateDataTimer(1.0, Timer_Weapon, hDataPack, TIMER_REPEAT);
		WritePackCell(hDataPack, EntIndexToEntRef(weapon));
		WritePackCell(hDataPack, weapon);
	}
}

public Action:Timer_Weapon(Handle:timer, Handle:hDataPack)
{
	ResetPack(hDataPack);
	
	new weaponRef = EntRefToEntIndex(ReadPackCell(hDataPack));
	new weapon = ReadPackCell(hDataPack);
	
	if (weaponRef == INVALID_ENT_REFERENCE)
	{
		/* Reference wasn't valid - Entity must have been deleted */
		g_Weapon[weapon][WeaponTimer] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_Weapon[weapon][Time] > 0)
	{
		g_Weapon[weapon][Time]--;
		return Plugin_Continue;
	}
	else
	{
		g_Weapon[weapon][WeaponTimer] = INVALID_HANDLE;
		return Plugin_Stop;
	}
}

public Hook_WeaponEquipPost(client, weapon)
{
	if (!IsValidClient(client) || !IsValidEdict(weapon))
		return;
	
	/*
	if (IsClientInLastRequest(client) > 0)
		return;
	*/
	
	decl String:sWeaponName[64];
	GetEdictClassname(weapon, sWeaponName, sizeof(sWeaponName));
	
	if (!IsWeaponOK(sWeaponName))
		return;
	
	switch (GetClientTeam(client))
	{
		case 2: // Terrorist
		{
			if (g_Weapon[weapon][WeaponTimer] != INVALID_HANDLE)
			{
				new bool:bCTDisconnected;
				new ct = GetClientOfUserId(g_Weapon[weapon][CTUserID]);
				
				if (!ct)
					bCTDisconnected = true;
				
				if (!bCTDisconnected && !g_bCTKilled[ct])
				{
					KillTimer(g_Weapon[weapon][WeaponTimer]);
					g_Weapon[weapon][WeaponTimer] = INVALID_HANDLE;
					
					// The CT dropped his gun naturally without getting killed (by pressing G)
					LogToAdmins(g_Weapon[weapon][CTName], client, sWeaponName, false);
				}
				else if (bCTDisconnected)
				{
					KillTimer(g_Weapon[weapon][WeaponTimer]);
					g_Weapon[weapon][WeaponTimer] = INVALID_HANDLE;
					
					// The CT dropped his gun, left the server and a T picked it up
					LogToAdmins(g_Weapon[weapon][CTName], client, sWeaponName, true);
				}
			}
		}
		case 3: // Counter-Terrorist
		{
			if (g_Weapon[weapon][WeaponTimer] != INVALID_HANDLE)
			{
				KillTimer(g_Weapon[weapon][WeaponTimer]);
				g_Weapon[weapon][WeaponTimer] = INVALID_HANDLE;
			}
		}
		default: return;
	}
}

stock bool:IsValidClient(client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)) return false;
	return true;
}

stock bool:IsAdmin(client)
{
	new AdminId:admin = GetUserAdmin(client);
	new bool:customFlag = GetAdminFlag(AdminId:admin, AdminFlag:ADMIN_FLAG);
	if (customFlag) return true;
	return false;
}

stock bool:IsWeaponOK(const String:sWeaponName[])
{
	if (StrContains(sWeaponName, "weapon_", false) != -1)
	{
		if (StrContains(sWeaponName, "grenade", false) != -1
		|| StrContains(sWeaponName, "flashbang", false) != -1
		|| StrContains(sWeaponName, "knife", false) != -1)
		{
			return false;
		}
		return true;
	}
	return false;
}

void LogToAdmins(const String:sCTName[], client, const String:sWeaponName[], bool:bCTDisconnected)
{
	decl String:sRoundTime[16];
	CalculateRoundTime(sRoundTime, sizeof(sRoundTime));
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsAdmin(i)) continue;
		
		if (!bCTDisconnected)
			PrintToConsole(i, "[Gunplant Log] %s gunplanted %N with %s at roundtime: %s", sCTName, client, sWeaponName, sRoundTime);
		else
			PrintToConsole(i, "[Gunplant Log] %s disconnected and gunplanted %N with %s at roundtime: %s", sCTName, client, sWeaponName, sRoundTime);
	}
}

void CalculateRoundTime(String:buffer[], maxlen)
{
	new t = (RoundToFloor(GetGameTime() - g_fGameTime) - g_FreezeTime + 60);
	new m;
	
	if (t >= 60)
	{
		m = RoundToFloor(t / 60.0);
		t = t % 60;
	}
	
	t = 60 - t;
	m = g_RoundTime - m;
	
	if (t % 60 == 0)
		m++;
	
	if (m < 0)
	{
		m = 0;
		t = 0;
	}
	
	Format(buffer, maxlen, "%i:%02i", m, t % 60);
}
