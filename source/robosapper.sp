#include <sdktools>
#include <tf2_stocks>

Handle hudText;

float sapperCooldown[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[TF2] RoboSapper",
	author = "Officer Spy",
	description = "Let players sap human players on the invading team in MvM.",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	RegAdminCmd("sm_recharge", Command_Recharge, ADMFLAG_GENERIC);
	
	HookEvent("player_death", Event_PlayerDeath);
	
	hudText = CreateHudSynchronizer();
}

public void OnClientPutInServer(int client)
{
	sapperCooldown[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (client <= 0)
		return Plugin_Handled;
	
	if (!IsClientConnected(client) || IsFakeClient(client))
		return Plugin_Continue;
	
	if (buttons & IN_ATTACK && CanUseSapper(client))
	{
		float clientOrigin[3];
		GetClientAbsOrigin(client, clientOrigin);
		
		int target = GetClientAimTarget(client, true);
		
		//Invalid client entity
		if (!IsValidEntity(target))
			return Plugin_Continue;
		
		float targetOrigin[3];
		GetClientAbsOrigin(target, targetOrigin);
		
		//Are we within range to sap?
		if (GetVectorDistance(clientOrigin, targetOrigin) < 130.0 && !IsFakeClient(target))
		{
			ApplyRoboSapper(client, target, 4.0, 0);
			return Plugin_Continue;
		}
	}
	
	//Prevent players from using the sapper after sapping a robot.
	float cooldownTime = sapperCooldown[client] - GetGameTime();
	if (cooldownTime > 0.0)
	{
		if (GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == GetPlayerWeaponSlot(client, 1))
		{
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", GetPlayerWeaponSlot(client, TFWeaponSlot_Melee)); //TODO: find a better way to do this.
		}
		
		//Show the player how much longer to before we can use the sapper.
		SetHudTextParams(-0.7, 0.8, 0.1, 0, 0, 255, 255);
		ShowSyncHudText(client, hudText, "Sapper recharge: %d", RoundFloat(cooldownTime));
	}
	
	return Plugin_Continue;
}

public Action Command_Recharge(int client, int args)
{
	int sapper = GetPlayerWeaponSlot(client, 1);
	
	SetEntPropFloat(sapper, Prop_Send, "m_flEffectBarRegenTime", 0.1);
	
	return Plugin_Handled;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	sapperCooldown[client] = 0.0;
}

public Action Timer_KillerSapperModel(Handle timer, int sapper)
{
	if (IsValidEntity(sapper))
	{
		EmitSoundToAll("weapons/sapper_removed.wav", sapper);
		StopSound(sapper, 0, "weapons/sapper_timer.wav");
		AcceptEntityInput(sapper, "kill")
	}
}

//Recreated checks to determine whether the player can use their sapper.
bool CanUseSapper(int client)
{
	//For spies only.
	if (TF2_GetPlayerClass(client) != TFClass_Spy)
		return false;
	
	//Sappers should always be in slot 1, though I feel like there should be a better way of doing this.
	if (GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != GetPlayerWeaponSlot(client, 1))
		return false;
	
	//We cannot use your sapper understand these conditions.
	if (TF2_IsPlayerInCondition(client, TFCond_Cloaked) || TF2_IsPlayerInCondition(client, TFCond_Dazed))
		return false;
	
	return true;
}

//Valid player to apply RoboSapper effects to?
stock bool IsValidRoboSapperTarget(int client)
{
	if (!IsPlayerAlive(client))
		return false;
	
	//In MvM, we only care about the invading team.
	if (TF2_GetClientTeam(client) != TFTeam_Blue)
		return false;
	
	if (IsInvulnerable(client))
		return false;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Bonked))
		return false;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Sapped))
		return false;
	
	if (TF2_IsPlayerInCondition(client, TFCond_Reprogrammed))
		return false;
	
	return true;
}

stock bool IsInvulnerable(int client)
{
	if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged)
	|| TF2_IsPlayerInCondition(client, TFCond_UberchargedHidden)
	|| TF2_IsPlayerInCondition(client, TFCond_UberchargedCanteen)
	|| TF2_IsPlayerInCondition(client, TFCond_PreventDeath))
	{
		return true;
	}
	
	return false;
}

stock void ApplyRoboSapper(int attacker, int target, float duration, int radius)
{
	if (IsValidRoboSapperTarget(target))
	{
		ApplyRoboSapperEffects(attacker, target, duration);
		sapperCooldown[attacker] = GetGameTime() + 15.0;
	}
	else
	{
		return;
	}
}

stock void ApplyRoboSapperEffects(int attacker, int target, float duration)
{
	if (IsMiniBoss(target))
	{
		TF2_StunPlayer(target, duration, 0.85, TF_STUNFLAG_SLOWDOWN, attacker);
	}
	else
	{
		TF2_StunPlayer(target, duration, 0.85, TF_STUNFLAGS_NORMALBONK|TF_STUNFLAG_LIMITMOVEMENT|TF_STUNFLAG_NOSOUNDOREFFECT, attacker);
	}
	TF2_AddCondition(target, TFCond_Sapped, duration, attacker);
	
	AttachSapperModel(target, duration);
}

stock bool IsMiniBoss(int client)
{
	return !!GetEntProp(client, Prop_Send, "m_bIsMiniBoss");
}

//Attaches the sapper model to the client.
stock void AttachSapperModel(int client, float duration)
{
	char sapperModel[256];
	sapperModel = "models/buildables/sapper_sentry1.mdl";
	
	int sapper = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(sapper, "targetname", "robosapper");
	DispatchKeyValue(sapper, "solid", "0");
	DispatchKeyValue(sapper, "model", sapperModel);
	SetVariantString("!activator");
	AcceptEntityInput(sapper, "SetParent", client, sapper, 0);
	SetVariantString("head");
	AcceptEntityInput(sapper, "SetParentAttachment", sapper , sapper, 0);
	DispatchSpawn(sapper);
	CreateTimer(duration, Timer_KillerSapperModel, sapper);
	SetEntProp(sapper, Prop_Send, "m_hOwnerEntity", client);
	
	EmitSoundToAll("weapons/sapper_plant.wav", sapper);
	EmitSoundToAll("weapons/sapper_timer.wav", sapper);
}