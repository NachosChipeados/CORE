//=========================================================
// Control Panels
//
//=========================================================

//////////////////////////////////////////////////////////////////////
function main()
{
	PrecacheModel( "models/communication/terminal_usable_imc_01.mdl" )
	PrecacheParticleSystem( "ar_titan_droppoint" )

	PrecacheMaterial( "vgui/hud/control_panel/console_disabled/console_disabled" )
	PrecacheMaterial( "vgui/hud/control_panel/console_f_deploy/console_f_deploy" )
	PrecacheMaterial( "vgui/hud/control_panel/console_f_search/console_f_search" )
	PrecacheMaterial( "vgui/hud/control_panel/console_f_active/console_f_active" )
	PrecacheMaterial( "vgui/hud/control_panel/console_f_repair/console_f_repair" )
	PrecacheMaterial( "vgui/hud/control_panel/console_e_deploy/console_e_deploy" )
	PrecacheMaterial( "vgui/hud/control_panel/console_e_search/console_e_search" )
	PrecacheMaterial( "vgui/hud/control_panel/console_e_active/console_e_active" )
	PrecacheMaterial( "vgui/hud/control_panel/console_e_repair/console_e_repair" )

	AddSpawnCallback( "prop_rush_panel", 			OnRushPanelSpawn )

	Globalize( SetRushPanelUsableToEnemies )

	RegisterSignal( "PanelReprogrammed" )
	RegisterSignal( "PanelReprogram_Success" )
	RegisterSignal( "OnContinousUseStopped" )

	level.rushPanels <- []
}

//////////////////////////////////////////////////////////
function GameModeRemoveRushPanel( ent )
{
	local keepUndefined
	local gameMode = GameRules.GetGameMode()

	switch ( gameMode )
	{
		// if we are in this game mode, then don't keep undefined panels
		case BIG_BROTHER:
		
		case HEIST:
			gameMode = BIG_BROTHER
			keepUndefined = true
			break

		case TITAN_RUSH:
			gameMode = TITAN_RUSH
			keepUndefined = true
			break

		default:
			keepUndefined = true
			gameMode = TEAM_DEATHMATCH
			break
	}

	local gamemodeKey = "gamemode_" + gameMode

	if ( ent.HasKey( gamemodeKey ) && ent.kv[gamemodeKey] == "1" )
	{
		// the key exists and it's true so keep it
		return
	}

	if ( !ent.HasKey( gamemodeKey ) && keepUndefined )
	{
		// the key doesn't exist but keepUndefined is true so still keep it
		return
	}

	ent.Destroy()
}


//////////////////////////////////////////////////////////////////////
function OnRushPanelSpawn( panel )
{
	Assert( panel.GetModelName() == "models/communication/terminal_usable_imc_01.mdl" )

	thread OnRushPanelSpawn_Internal( panel )
}

//////////////////////////////////////////////////////////////////////
function OnRushPanelSpawn_Internal( panel )
{	
	panel.EndSignal( "OnDestroy" )
	GameModeRemoveRushPanel( panel )

	panel.s.useFuncArray <- []

	Assert( IsValid( panel ), "Invalid panel " + panel )
	panel.EndSignal( "OnDestroy" )

	level.rushPanels.append( panel )
	//Default, set it usable by everyone
	panel.SetUsableByGroup( "pilot" )

	panel.useFunction = ControlPanel_CanUseFunction

	panel.s.leechTimeNormal <- 3.0
	panel.s.leechTimeFast <- 1.1

	// custom functions you can create for when the panel starts or stops hacking
	panel.s.panelHackStartFunc <- null
	panel.s.panelHackEndFunc <- null
	panel.s.panelHackScope <- null

	// 패널이 해킹된 횟수
	panel.s.hackedCount <- 0

	for ( ;; )
	{
		local results = panel.WaitSignal( "OnPlayerUse" )
		local player = results.activator

		Assert( IsPlayer( player ) )

		if ( !IsAlive( player ) || player.IsTitan()  )
			continue

		// already a user?
		if ( IsAlive( panel.GetBossPlayer() ) )
			continue

/*
		if ( !panel.useFunction( player, panel ) )
		{
			//play buzzer sound
			EmitSoundOnEntity( panel, "Operator.Ability_offline" )
			wait 1
			continue
		}
*/
		waitthread PlayerUsesRushPanel( player, panel )
	}
}

function PlayerUsesRushPanel( player, panel )
{
	thread PlayerProgramsRushPanel( panel, player )

	local result = panel.WaitSignal( "PanelReprogrammed" )

	if ( result.success )
	{
		panel.Signal( "PanelReprogram_Success" )

		local panelEHandle = IsValid( panel ) ? panel.GetEncodedEHandle() : null
		local players = GetPlayerArray()
		foreach( player in players )
		{
			Remote.CallFunction_Replay( player, "ServerCallback_RushPanelRefresh", panelEHandle )
		}

		RunRushPanelUseFunctions( panel, player )
	}
	else
	{
		//play buzzer sound
		EmitSoundOnEntity( panel, "Operator.Ability_offline" )
		wait 0	// arbitrary delay so that you can't restart the leech instantly after failing
	}
}

function RunRushPanelUseFunctions( panel, player )
{
	if ( panel.s.useFuncArray.len() <= 0 )
		return

	foreach ( useFuncTable in clone panel.s.useFuncArray )
	{
		if ( useFuncTable.useEnt == null )
			useFuncTable.useFunc.acall( [useFuncTable.scope, panel, player] )
		else
			useFuncTable.useFunc.acall( [useFuncTable.scope, panel, player, useFuncTable.useEnt] )
	}
}

function SetRushPanelUseFunc( panel, func, scope, ent = null )
{
	local table = InitRushPanelUseFuncTable()
	table.useFunc <- func
	table.useEnt <- ent
	table.scope <- scope
	AddRushPanelUseFuncTable( panel, table )
}
Globalize( SetRushPanelUseFunc )

//////////////////////////////////////////////////////////////////////
function PlayerProgramsRushPanel( panel, player )
{
	Assert( IsAlive( player ) )
	player.EndSignal( "Disconnected" )
	player.EndSignal( "OnDeath" )
	player.EndSignal( "ScriptAnimStop" )

	// need to wait here so that the panel script can start waiting for the PanelReprogrammed signal.
	wait 0

	local action =
	{
		playerAnimation1pStart = "ptpov_data_knife_console_leech_start"
		playerAnimation1pIdle = "ptpov_data_knife_console_leech_idle"
		playerAnimation1pEnd = "ptpov_data_knife_console_leech_end"

		playerAnimation3pStart = "pt_data_knife_console_leech_start"
		playerAnimation3pIdle = "pt_data_knife_console_leech_idle"
		playerAnimation3pEnd = "pt_data_knife_console_leech_end"

		panelAnimation3pStart = "tm_data_knife_console_leech_start"
		panelAnimation3pIdle = "tm_data_knife_console_leech_idle"
		panelAnimation3pEnd = "tm_data_knife_console_leech_end"

		direction = Vector( -1, 0, 0 )
		targetClass = "npc_marvin" // ???
	}

	local e = {}
	e.success <- false
	e.knives <- []

	e.ranPanelEndFunc <- false

	// make it so it's only usable by the player that started the leech
	e.panelUsableValue <- panel.GetUsableValue()

	e.startOrigin <- player.GetOrigin()
	panel.SetBossPlayer( player )
	panel.SetUsableByGroup( "owner pilot" )

	e.setIntruder <- false

	player.ForceStand()

	OnThreadEnd
	(
		function() : ( e, player, panel )
		{
			if ( e.setIntruder )
				level.nv.panelIntruder = null

			if ( IsValid( player ) )
			{
				player.ClearAnimNearZ()
				player.ClearParent()

				// stop any running first person sequences
				player.Anim_Stop()

				// stop dataknife animating and making sounds
				Remote.CallFunction_Replay( player, "ServerCallback_DataKnifeCancelLeech" )

				if ( IsAlive( player ) )
				 	UnStuck( player, e.startOrigin, panel )

				// done with first person anims
				player.ClearAnimViewEntity()
				player.DeployWeapon()
				player.UnforceStand()

				if ( player.ContextAction_IsLeeching() )
					player.Event_LeechEnd()
			}

			if ( IsValid( panel ) )
			{
				if ( !e.ranPanelEndFunc && panel.s.panelHackEndFunc )
					thread panel.s.panelHackEndFunc.acall( [panel.s.panelHackScope, panel, player] )

				// reset panel

				// stop any running first person sequences
				panel.Anim_Stop()
				panel.Anim_Play( "ref" ) // close the hatch

				// reset default usability
				panel.ClearBossPlayer()

				if ( !e.success )
				{
					panel.Signal( "PanelReprogrammed", { success = e.success } )
					local turret = GetMegaTurretLinkedToPanel( panel ) //CHIN: Control panels shouldn't need to know about turrets
					if ( IsValid( turret ) && turret.IsTurret() )
					{
						local usableValue = MegaTurretUsabilityFunc( turret, panel )
						panel.SetUsableByGroup( usableValue )
						SetUsePromptForRushPanel( panel, turret )
					}
					else
					{
						// Turret got destoyed while hacking.
						// Usability state has been set by ReleaseTurret( ... ) in ai_turret.nut
						// Changing it to the previous usable value would put us in a bad state.

						// training level a hackable panel that isn't hooked up to a turret.
						// In this case we need to reset the usable value to what it used to be
						// we should change how this works for R2
						if (GetMapName() == "mp_npe")
						 	panel.SetUsableValue( e.panelUsableValue )
					}

				}

			}

			foreach ( knife in e.knives )
			{
				if ( IsValid( knife ) )
					knife.Kill()
			}
		}
	)

	if ( !player.UseButtonPressed() )
		return	// it's possible to get here and no longer be holding the use button. If that is the case lets not continue.

	if ( player.ContextAction_IsActive() )
		return

	player.HolsterWeapon()
	player.SetAnimNearZ( 1 )

	player.Event_LeechStart()

	local leechTime = panel.s.leechTimeNormal

	if ( PlayerHasPassive( player, PAS_FAST_HACK ) )
		leechTime = panel.s.leechTimeFast

	local knifeIn = false
	local totalTime = leechTime + player.GetSequenceDuration( action.playerAnimation3pStart )

	thread TrackContinuousUse( player, totalTime )

	// The data knife needs to be turned off, or it could be drawing whatever
	// was last on it
	Remote.CallFunction_Replay( player, "ServerCallback_DataKnifeReset" )

	if ( panel.s.panelHackStartFunc )
	{
		thread panel.s.panelHackStartFunc.acall( [panel.s.panelHackScope, panel, player] )
	}

	waitthread RushPanelFlipAnimation( panel, player, action, e )

	if ( !player.UseButtonPressed() )
		return	// we might have returned from the flip anim because we released the use button.

	Remote.CallFunction_Replay( player, "ServerCallback_DataKnifeStartLeech", leechTime )

	waitthread WaitForEndLeechOrStoppedUse( player, leechTime, e, panel )

	if ( panel.s.panelHackEndFunc )
	{
		e.ranPanelEndFunc = true
		thread panel.s.panelHackEndFunc.acall( [panel.s.panelHackScope, panel, player] )
	}

	waitthread RushPanelFlipExitAnimation( player, panel, action, e )
}

function WaitForEndLeechOrStoppedUse( player, leechTime, e, panel )
{
	player.EndSignal( "OnContinousUseStopped" )
	wait leechTime
	e.success = true
	panel.Signal( "PanelReprogrammed", { success = e.success } )
}


//////////////////////////////////////////////////////////////////////
function RushPanelFlipAnimation( panel, player, action, e )
{
//	OnThreadEnd
//	(
//		function() : ( panel )
//		{
//			if ( IsValid( panel ) )
//				DeleteAnimEvent( panel, "knife_popout", KnifePopOut )
//		}
//	)
	player.EndSignal( "OnContinousUseStopped" )

	local playerSequence = CreateFirstPersonSequence()
	playerSequence.blendTime = 0.25
	playerSequence.attachment = "ref"
	playerSequence.thirdPersonAnim = action.playerAnimation3pStart
	playerSequence.thirdPersonAnimIdle = action.playerAnimation3pIdle
	playerSequence.firstPersonAnim = action.playerAnimation1pStart
	playerSequence.firstPersonAnimIdle = action.playerAnimation1pIdle
	if ( IntroPreviewOn() )
		playerSequence.viewConeFunction = ControlPanelFlipViewCone

	local panelSequence = CreateFirstPersonSequence()
	panelSequence.blendTime = 0.25
	panelSequence.thirdPersonAnim = action.panelAnimation3pStart
	panelSequence.thirdPersonAnimIdle = action.panelAnimation3pIdle


	local model = DATA_KNIFE_MODEL
	//AddAnimEvent( panel, "knife_popout", KnifePopOut, e )
	//local knife = CreatePropDynamic( model )
	//knife.SetName( "dataKnife" )
	//knife.SetParent( player.GetFirstPersonProxy(), "propgun", false, 0.0 )
	//e.knives.append( knife )

	local knife = CreatePropDynamic( model )
	knife.SetName( "dataKnife" )
	knife.SetParent( player, "propgun", false, 0.0 )
	e.knives.append( knife )

	thread PanelFirstPersonSequence( panelSequence, panel, player )
	waitthread FirstPersonSequence( playerSequence, player, panel )
}


function RushPanelFlipViewCone( player )
{
	player.PlayerCone_FromAnim()
	player.PlayerCone_SetMinYaw( -80 )
	player.PlayerCone_SetMaxYaw( 80 )
	player.PlayerCone_SetMinPitch( -80 )
	player.PlayerCone_SetMaxPitch( 10 )
}


//////////////////////////////////////////////////////////////////////
function KnifePopOut( player, e )
{
	foreach ( knife in e.knives )
	{
		knife.Anim_Play( "data_knife_console_leech_start" )
	}
}


//////////////////////////////////////////////////////////////////////
function PanelFirstPersonSequence( panelSequence, panel, player )
{
	player.EndSignal( "Disconnected" )
	player.EndSignal( "OnDeath" )
	panel.EndSignal( "OnDestroy" )

	waitthread FirstPersonSequence( panelSequence, panel )
}


//////////////////////////////////////////////////////////////////////
function RushPanelFlipExitAnimation( player, panel, action, e )
{
	local playerSequence = CreateFirstPersonSequence()
	playerSequence.blendTime = 0.0
	playerSequence.attachment = "ref"
	playerSequence.teleport = true

	local panelSequence = CreateFirstPersonSequence()
	panelSequence.blendTime = 0.0

	playerSequence.thirdPersonAnim = action.playerAnimation3pEnd
	playerSequence.firstPersonAnim = action.playerAnimation1pEnd
	panelSequence.thirdPersonAnim = action.panelAnimation3pEnd

	thread FirstPersonSequence( panelSequence, panel )
	waitthread FirstPersonSequence( playerSequence, player, panel )
}


//////////////////////////////////////////////////////////////////////
function TrackContinuousUse( player, leechTime )
{
	player.EndSignal( "Disconnected" )
	player.EndSignal( "OnDeath" )
	player.EndSignal( "ScriptAnimStop" )

	local result = {}
	result.success <- false

	OnThreadEnd
	(
		function() : ( player, result )
		{
			if ( !result.success )
			{
				player.Signal( "OnContinousUseStopped" )
			}
		}
	)

	ButtonUnpressedEndSignal( player, "use" )

	if ( !player.UseButtonPressed() )
		return

	wait leechTime
	result.success = true
}

function InitRushPanelUseFuncTable()
{
	local table = {}
	table.useEnt <- null
	table.useFunc <- null
	table.scope <- null
	return table
}

function AddRushPanelUseFuncTable( panel, table )
{
	// a table that contains
	//1. a function to be called when the control panel is used
	//2. an entity that the function refers to, e.g. the turret to be created
	panel.s.useFuncArray.append( table )
}

function SetRushPanelUsableToEnemies( panel )
{
	if ( panel.GetTeam() == TEAM_IMC || panel.GetTeam() == TEAM_MILITIA  )
	{
		panel.SetUsableByGroup( "enemies pilot" )
		return
	}

	//Not on either player team, just set usable to everyone
	panel.SetUsableByGroup( "pilot" )
}