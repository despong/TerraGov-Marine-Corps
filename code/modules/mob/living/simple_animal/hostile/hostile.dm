/mob/living/simple_animal/hostile
	faction = FACTION_HOSTILE
	stop_automated_movement_when_pulled = 0
	obj_damage = 40
	wall_smash = TRUE
	var/atom/target
	var/ranged = FALSE
	var/rapid = 0 //How many shots per volley.
	var/rapid_fire_delay = 2 //Time between rapid fire shots

	var/dodging = FALSE
	var/approaching_target = FALSE //We should dodge now
	var/in_melee = FALSE	//We should sidestep now
	var/dodge_prob = 30
	var/sidestep_per_cycle = 1 //How many sidesteps per npcpool cycle when in melee

	var/ammotype = /datum/ammo/bullet/pistol
	var/projectilesound
	var/casingtype = /obj/item/ammo_casing/bullet
	var/move_to_delay = 3 //delay for the automated movement.
	var/list/friends = list()
	var/list/emote_taunt = list()
	var/taunt_chance = 0

	var/rapid_melee = 1			 //Number of melee attacks between each npc pool tick. Spread evenly.
	var/melee_queue_distance = 4 //If target is close enough start preparing to hit them if we have rapid_melee enabled

	var/ranged_message = "fires" //Fluff text for ranged mobs
	var/ranged_cooldown = 0 //What the current cooldown on ranged attacks is, generally world.time + ranged_cooldown_time
	var/ranged_cooldown_time = 30 //How long, in deciseconds, the cooldown of ranged attacks is
	var/ranged_ignores_vision = FALSE //if it'll fire ranged attacks even if it lacks vision on its target, only works with environment smash
	var/check_friendly_fire = 0 // Should the ranged mob check for friendlies when shooting
	var/retreat_distance = null //If our mob runs from players when they're too close, set in tile distance. By default, mobs do not retreat.
	var/minimum_distance = 1 //Minimum approach distance, so ranged mobs chase targets down, but still keep their distance set in tiles to the target, set higher to make mobs keep distance


//These vars are related to how mobs locate and target
	var/robust_searching = 0 //By default, mobs have a simple searching method, set this to 1 for the more scrutinous searching (stat_attack, stat_exclusive, etc), should be disabled on most mobs
	var/vision_range = 9 //How big of an area to search for targets in, a vision of 9 attempts to find targets as soon as they walk into screen view
	var/aggro_vision_range = 9 //If a mob is aggro, we search in this radius. Defaults to 9 to keep in line with original simple mob aggro radius
	var/search_objects = 0 //If we want to consider objects when searching around, set this to 1. If you want to search for objects while also ignoring mobs until hurt, set it to 2. To completely ignore mobs, even when attacked, set it to 3
	var/search_objects_timer_id //Timer for regaining our old search_objects value after being attacked
	var/search_objects_regain_time = 30 //the delay between being attacked and gaining our old search_objects value back
	var/list/wanted_objects = list() //A typecache of objects types that will be checked against to attack, should we have search_objects enabled
	var/stat_attack = CONSCIOUS //Mobs with stat_attack to UNCONSCIOUS will attempt to attack things that are unconscious, Mobs with stat_attack set to DEAD will attempt to attack the dead.
	var/stat_exclusive = FALSE //Mobs with this set to TRUE will exclusively attack things defined by stat_attack, stat_attack DEAD means they will only attack corpses
	var/attack_same = 0 //Set us to 1 to allow us to attack our own faction
	var/atom/targets_from = null //all range/attack/etc. calculations should be done from this atom, defaults to the mob itself, useful for Vehicles and such
	var/attack_all_objects = FALSE //if true, equivalent to having a wanted_objects list containing ALL objects.

	var/lose_patience_timer_id //id for a timer to call LoseTarget(), used to stop mobs fixating on a target they can't reach
	var/lose_patience_timeout = 300 //30 seconds by default, so there's no major changes to AI behaviour, beyond actually bailing if stuck forever

/mob/living/simple_animal/hostile/Initialize(mapload)
	. = ..()

	if(!targets_from)
		targets_from = src
	wanted_objects = typecacheof(wanted_objects)


/mob/living/simple_animal/hostile/Destroy()
	targets_from = null
	return ..()

/mob/living/simple_animal/hostile/Life(seconds_per_tick, times_fired)
	. = ..()
	if(!.) //dead
		walk(src, 0) //stops walking
		return 0

/mob/living/simple_animal/hostile/handle_automated_action()
	if(AIStatus == AI_OFF)
		return 0
	var/list/possible_targets = ListTargets() //we look around for potential targets and make it a list for later use.

	if(wall_smash)
		EscapeConfinement()

	if(AICanContinue(possible_targets))
		if(!QDELETED(target) && !targets_from.Adjacent(target))
			DestroyPathToTarget()
		if(!MoveToTarget(possible_targets))     //if we lose our target
			if(AIShouldSleep(possible_targets))	// we try to acquire a new one
				toggle_ai(AI_IDLE)			// otherwise we go idle
	return 1

/mob/living/simple_animal/hostile/handle_automated_movement()
	. = ..()
	if(dodging && target && in_melee && isturf(loc) && isturf(target.loc))
		var/datum/cb = CALLBACK(src,PROC_REF(sidestep))
		if(sidestep_per_cycle > 1) //For more than one just spread them equally - this could changed to some sensible distribution later
			var/sidestep_delay = SSnpcpool.wait / sidestep_per_cycle
			for(var/i in 1 to sidestep_per_cycle)
				addtimer(cb, (i - 1)*sidestep_delay)
		else //Otherwise randomize it to make the players guessing.
			addtimer(cb,rand(1,SSnpcpool.wait))

/mob/living/simple_animal/hostile/proc/sidestep()
	if(!target || !isturf(target.loc) || !isturf(loc) || stat == DEAD)
		return
	var/target_dir = get_dir(src,target)

	var/static/list/cardinal_sidestep_directions = list(-90,-45,0,45,90)
	var/static/list/diagonal_sidestep_directions = list(-45,0,45)
	var/chosen_dir = 0
	if (target_dir & (target_dir - 1))
		chosen_dir = pick(diagonal_sidestep_directions)
	else
		chosen_dir = pick(cardinal_sidestep_directions)
	if(chosen_dir)
		chosen_dir = turn(target_dir,chosen_dir)
		Move(get_step(src,chosen_dir))
		face_atom(target) //Looks better if they keep looking at you when dodging


/mob/living/simple_animal/hostile/bullet_act(atom/movable/projectile/proj)
	if(stat == CONSCIOUS && !target && AIStatus != AI_OFF && !client)
		if(proj.firer && get_dist(src, proj.firer) <= aggro_vision_range)
			FindTarget(list(proj.firer), 1)
		Goto(proj.starting_turf, move_to_delay, 3)
	return ..()

//////////////HOSTILE MOB TARGETTING AND AGGRESSION////////////

/mob/living/simple_animal/hostile/proc/ListTargets()//Step 1, find out what we can see
	if(!search_objects)
		. = hearers(vision_range, targets_from) - src //Remove self, so we don't suicide

		for(var/HM in range(vision_range, targets_from))
			if(line_of_sight(targets_from, HM, vision_range))
				. += HM
	else
		. = list()
		for (var/atom/movable/A in oview(vision_range, targets_from))
			. += A

/mob/living/simple_animal/hostile/proc/FindTarget(list/possible_targets, HasTargetsList = 0)//Step 2, filter down possible targets to things we actually care about
	. = list()
	if(!HasTargetsList)
		possible_targets = ListTargets()
	for(var/pos_targ in possible_targets)
		var/atom/A = pos_targ
		if(Found(A))//Just in case people want to override targetting
			. = list(A)
			break
		if(CanAttack(A))//Can we attack it?
			. += A
			continue
	var/Target = PickTarget(.)
	GiveTarget(Target)
	return Target //We now have a target



/mob/living/simple_animal/hostile/proc/PossibleThreats()
	. = list()
	for(var/pos_targ in ListTargets())
		var/atom/A = pos_targ
		if(Found(A))
			. = list(A)
			break
		if(CanAttack(A))
			. += A
			continue



/mob/living/simple_animal/hostile/proc/Found(atom/A)//This is here as a potential override to pick a specific target if available
	return

/mob/living/simple_animal/hostile/proc/PickTarget(list/Targets)//Step 3, pick amongst the possible, attackable targets
	if(target != null)//If we already have a target, but are told to pick again, calculate the lowest distance between all possible, and pick from the lowest distance targets
		for(var/pos_targ in Targets)
			var/atom/A = pos_targ
			var/target_dist = get_dist(targets_from, target)
			var/possible_target_distance = get_dist(targets_from, A)
			if(target_dist < possible_target_distance)
				Targets -= A
	if(!length(Targets))//We didnt find nothin!
		return
	var/chosen_target = pick(Targets)//Pick the remaining targets (if any) at random
	return chosen_target

// Please do not add one-off mob AIs here, but override this function for your mob
/mob/living/simple_animal/hostile/CanAttack(atom/the_target)//Can we actually attack a possible target?
	if(isturf(the_target) || !the_target) // bail out on invalids
		return FALSE

	if(ismob(the_target)) //Target is in godmode, ignore it.
		var/mob/M = the_target
		if(M.status_flags & GODMODE)
			return FALSE

	if(see_invisible < the_target.invisibility)//Target's invisible to us, forget it
		return FALSE
	if(search_objects < 2)
		if(isliving(the_target))
			var/mob/living/L = the_target
			var/faction_check = faction == L.faction
			if(robust_searching)
				if(faction_check && !attack_same)
					return FALSE
				if(L.stat > stat_attack)
					return FALSE
				if(L in friends)
					return FALSE
			else
				if((faction_check && !attack_same) || L.stat)
					return FALSE
			return TRUE

	if(isobj(the_target))
		if(attack_all_objects || is_type_in_typecache(the_target, wanted_objects))
			return TRUE

	return FALSE

/mob/living/simple_animal/hostile/proc/GiveTarget(new_target)//Step 4, give us our selected target
	target = new_target
	LosePatience()
	if(target != null)
		GainPatience()
		Aggro()
		return 1

//What we do after closing in
/mob/living/simple_animal/hostile/proc/MeleeAction(patience = TRUE)
	if(rapid_melee > 1)
		var/datum/callback/cb = CALLBACK(src, PROC_REF(CheckAndAttack))
		var/delay = SSnpcpool.wait / rapid_melee
		for(var/i in 1 to rapid_melee)
			addtimer(cb, (i - 1)*delay)
	else
		AttackingTarget()
	if(patience)
		GainPatience()


/mob/living/simple_animal/hostile/proc/CheckAndAttack()
	if(target && targets_from && isturf(targets_from.loc) && target.Adjacent(targets_from) && !incapacitated())
		AttackingTarget()


/mob/living/simple_animal/hostile/proc/MoveToTarget(list/possible_targets)//Step 5, handle movement between us and our target
	stop_automated_movement = TRUE
	if(!target || !CanAttack(target))
		LoseTarget()
		return FALSE
	if(target in possible_targets)
		var/turf/T = get_turf(src)
		if(target.z != T.z)
			LoseTarget()
			return FALSE
		var/target_distance = get_dist(targets_from,target)
		if(ranged) //We ranged? Shoot at em
			if(!target.Adjacent(targets_from) && ranged_cooldown <= world.time) //But make sure they're not in range for a melee attack and our range attack is off cooldown
				OpenFire(target)
		if(!Process_Spacemove()) //Drifting
			walk(src, 0)
			return TRUE
		if(retreat_distance != null) //If we have a retreat distance, check if we need to run from our target
			if(target_distance <= retreat_distance) //If target's closer than our retreat distance, run
				walk_away(src,target,retreat_distance,move_to_delay)
			else
				Goto(target,move_to_delay,minimum_distance) //Otherwise, get to our minimum distance so we chase them
		else
			Goto(target,move_to_delay,minimum_distance)
		if(target)
			if(targets_from && isturf(targets_from.loc) && target.Adjacent(targets_from)) //If they're next to us, attack
				MeleeAction()
			else
				if(rapid_melee > 1 && target_distance <= melee_queue_distance)
					MeleeAction(FALSE)
				in_melee = FALSE //If we're just preparing to strike do not enter sidestep mode
			return TRUE
		return FALSE

	if(wall_smash)
		if(target.loc != null && get_dist(targets_from, target.loc) <= vision_range) //We can't see our target, but he's in our vision range still
			if(ranged_ignores_vision && ranged_cooldown <= world.time) //we can't see our target... but we can fire at them!
				OpenFire(target)
				Goto(target,move_to_delay,minimum_distance)
				FindHidden()
				return TRUE
			else
				if(FindHidden())
					return TRUE
	LoseTarget()
	return FALSE


/mob/living/simple_animal/hostile/proc/Goto(target, delay, minimum_distance)
	if(target == src.target)
		approaching_target = TRUE
	else
		approaching_target = FALSE
	walk_to(src, target, minimum_distance, delay)


/mob/living/simple_animal/hostile/adjustHealth(amount, updating_health = TRUE, forced = FALSE)
	. = ..()
	if(!ckey && !stat && search_objects < 3 && . > 0)//Not unconscious, and we don't ignore mobs
		if(search_objects)//Turn off item searching and ignore whatever item we were looking at, we're more concerned with fight or flight
			target = null
			LoseSearchObjects()
		if(AIStatus != AI_ON && AIStatus != AI_OFF)
			toggle_ai(AI_ON)
			FindTarget()
		else if(target != null && prob(40))//No more pulling a mob forever and having a second player attack it, it can switch targets now if it finds a more suitable one
			FindTarget()


/mob/living/simple_animal/hostile/proc/AttackingTarget()
	in_melee = TRUE
	return target.attack_animal(src)


/mob/living/simple_animal/hostile/proc/Aggro()
	vision_range = aggro_vision_range
	if(target && length(emote_taunt) && prob(taunt_chance))
		emote("me", 1, "[pick(emote_taunt)] at [target].")
		taunt_chance = max(taunt_chance-7,2)


/mob/living/simple_animal/hostile/proc/LoseAggro()
	stop_automated_movement = 0
	vision_range = initial(vision_range)
	taunt_chance = initial(taunt_chance)


/mob/living/simple_animal/hostile/proc/LoseTarget()
	target = null
	approaching_target = FALSE
	in_melee = FALSE
	walk(src, 0)
	LoseAggro()


/mob/living/simple_animal/hostile/on_death()
	LoseTarget()
	return ..()


/mob/living/simple_animal/hostile/proc/summon_backup(distance, eABILITY_faction_match)
	playsound(loc, 'sound/machines/chime.ogg', 50, 1, -1)
	for(var/mob/living/simple_animal/hostile/M in oview(distance, targets_from))
		if(faction == M.faction)
			if(M.AIStatus == AI_OFF)
				return
			else
				M.Goto(src, M.move_to_delay, M.minimum_distance)


/mob/living/simple_animal/hostile/proc/CheckFriendlyFire(atom/A)
	if(check_friendly_fire)
		for(var/turf/T in get_traversal_line(src,A)) // Not 100% reliable but this is faster than simulating actual trajectory
			for(var/mob/living/L in T)
				if(L == src || L == A)
					continue
				if(faction == L.faction && !attack_same)
					return TRUE


/mob/living/simple_animal/hostile/proc/OpenFire(atom/A)
	if(CheckFriendlyFire(A))
		return
	visible_message(span_danger("<b>[src]</b> [ranged_message] at [A]!"))


	if(rapid > 1)
		var/datum/callback/cb = CALLBACK(src, PROC_REF(Shoot), A)
		for(var/i in 1 to rapid)
			addtimer(cb, (i - 1)*rapid_fire_delay)
	else
		Shoot(A)
	ranged_cooldown = world.time + ranged_cooldown_time


/mob/living/simple_animal/hostile/proc/Shoot(atom/targeted_atom)
	if(QDELETED(targeted_atom) || targeted_atom == targets_from.loc || targeted_atom == targets_from)
		return
	var/turf/startloc = get_turf(targets_from)
	new casingtype(startloc)
	playsound(src, projectilesound, 100, 1)
	var/atom/movable/projectile/P = new(startloc)
	playsound(src, projectilesound, 100, 1)
	P.generate_bullet(GLOB.ammo_list[ammotype])
	P.fire_at(targeted_atom, src, src)


/mob/living/simple_animal/hostile/proc/CanSmashTurfs(turf/T)
	return iswallturf(T) || ismineralturf(T)


/mob/living/simple_animal/hostile/Move(atom/newloc, direction, glide_size_override)
	if(dodging && approaching_target && prob(dodge_prob) && isturf(loc) && isturf(newloc))
		return dodge(newloc,dir)
	else
		return ..()

/mob/living/simple_animal/hostile/proc/dodge(moving_to, move_direction)
	//Assuming we move towards the target we want to swerve toward them to get closer
	var/cdir = turn(move_direction,45)
	var/ccdir = turn(move_direction,-45)
	dodging = FALSE
	. = Move(get_step(loc,pick(cdir,ccdir)))
	if(!.)//Can't dodge there so we just carry on
		. = Move(moving_to,move_direction)
	dodging = TRUE


/mob/living/simple_animal/hostile/proc/DestroyObjectsInDirection(direction)
	var/turf/T = get_step(targets_from, direction)
	if(QDELETED(T))
		return
	if(T.Adjacent(targets_from))
		if(CanSmashTurfs(T))
			T.attack_animal(src)
			return
	for(var/obj/O in T.contents)
		if(!O.Adjacent(targets_from))
			continue
		if((ismachinery(O) || isstructure(O)) && O.density && wall_smash)
			O.attack_animal(src)
			return

/mob/living/simple_animal/hostile/proc/DestroyPathToTarget()
	if(wall_smash)
		EscapeConfinement()
		var/dir_to_target = get_dir(targets_from, target)
		var/dir_list = list()
		if(dir_to_target in GLOB.diagonals) //it's diagonal, so we need two directions to hit
			for(var/direction in GLOB.cardinals)
				if(direction & dir_to_target)
					dir_list += direction
		else
			dir_list += dir_to_target
		for(var/direction in dir_list) //now we hit all of the directions we got in this fashion, since it's the only directions we should actually need
			DestroyObjectsInDirection(direction)


/mob/living/simple_animal/hostile/proc/DestroySurroundings() // for use with megafauna destroying everything around them
	if(wall_smash)
		EscapeConfinement()
		for(var/dir in GLOB.cardinals)
			DestroyObjectsInDirection(dir)


/mob/living/simple_animal/hostile/proc/EscapeConfinement()
	if(buckled)
		buckled.attack_animal(src)
	if(!isturf(targets_from.loc) && targets_from.loc != null)//Did someone put us in something?
		var/atom/A = targets_from.loc
		A.attack_animal(src)//Bang on it till we get out


/mob/living/simple_animal/hostile/proc/FindHidden()
	if(istype(target.loc, /obj/structure/closet) || istype(target.loc, /obj/machinery/disposal) || istype(target.loc, /obj/machinery/sleeper))
		var/atom/A = target.loc
		Goto(A,move_to_delay,minimum_distance)
		if(A.Adjacent(targets_from))
			A.attack_animal(src)
		return 1


/mob/living/simple_animal/hostile/RangedAttack(atom/A, params) //Player firing
	if(ranged && ranged_cooldown <= world.time)
		target = A
		OpenFire(A)
	return ..()


/mob/living/simple_animal/hostile/proc/AICanContinue(list/possible_targets)
	switch(AIStatus)
		if(AI_ON)
			. = TRUE
		if(AI_IDLE)
			if(FindTarget(possible_targets, 1))
				. = TRUE
				toggle_ai(AI_ON) //Wake up for more than one Life() cycle.
			else
				. = FALSE

/mob/living/simple_animal/hostile/proc/AIShouldSleep(list/possible_targets)
	return !FindTarget(possible_targets, 1)


//These two procs handle losing our target if we've failed to attack them for
//more than lose_patience_timeout deciseconds, which probably means we're stuck
/mob/living/simple_animal/hostile/proc/GainPatience()
	if(lose_patience_timeout)
		LosePatience()
		lose_patience_timer_id = addtimer(CALLBACK(src, PROC_REF(LoseTarget)), lose_patience_timeout, TIMER_STOPPABLE)


/mob/living/simple_animal/hostile/proc/LosePatience()
	deltimer(lose_patience_timer_id)


//These two procs handle losing and regaining search_objects when attacked by a mob
/mob/living/simple_animal/hostile/proc/LoseSearchObjects()
	search_objects = 0
	deltimer(search_objects_timer_id)
	search_objects_timer_id = addtimer(CALLBACK(src, PROC_REF(RegainSearchObjects)), search_objects_regain_time, TIMER_STOPPABLE)


/mob/living/simple_animal/hostile/proc/RegainSearchObjects(value)
	if(!value)
		value = initial(search_objects)
	search_objects = value


/mob/living/simple_animal/hostile/consider_wakeup()
	. = ..()
	var/list/tlist
	var/turf/T = get_turf(src)

	if(!T)
		return

	if(!length(SSmobs.clients_by_zlevel[T.z]))
		toggle_ai(AI_Z_OFF)
		return

	var/cheap_search = isturf(T) && !is_station_level(T.z)
	if (cheap_search)
		tlist = ListTargetsLazy(T.z)
	else
		tlist = ListTargets()

	if(AIStatus == AI_IDLE && FindTarget(tlist, 1))
		if(cheap_search) //Try again with full effort
			FindTarget()
		toggle_ai(AI_ON)


/mob/living/simple_animal/hostile/proc/ListTargetsLazy(z_level)
	. = list()
	for(var/i in SSmobs.clients_by_zlevel[z_level])
		var/mob/M = i
		if(get_dist(M, src) < vision_range)
			if(isturf(M.loc))
				. += M
