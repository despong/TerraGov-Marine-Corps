/datum/wires/apc
	holder_type = /obj/machinery/power/apc
	proper_name = "APC"


/datum/wires/apc/New(atom/holder)
	wires = list(
		WIRE_POWER1, WIRE_POWER2,
		WIRE_IDSCAN, WIRE_AI
	)
	add_duds(6)
	return ..()


/datum/wires/apc/can_interact(mob/user)
	. = ..()
	if(!.)
		return FALSE
	var/obj/machinery/power/apc/A = holder
	return CHECK_BITFIELD(A.machine_stat, PANEL_OPEN) && !A.opened


/datum/wires/apc/get_status()
	var/obj/machinery/power/apc/A = holder
	var/list/status = list()
	status += "The interface light is [A.locked ? "red" : "green"]."
	status += "The short indicator is [A.shorted ? "lit" : "off"]."
	status += "The AI connection light is [!A.aidisabled ? "on" : "off"]."
	return status


/datum/wires/apc/on_pulse(wire)
	var/obj/machinery/power/apc/A = holder
	switch(wire)
		if(WIRE_POWER1, WIRE_POWER2) // Short for a long while.
			if(!A.shorted)
				A.shorted = TRUE
				addtimer(CALLBACK(A, TYPE_PROC_REF(/obj/machinery/power/apc, reset), wire), 1200)
		if(WIRE_IDSCAN) // Unlock for a little while.
			A.locked = FALSE
			addtimer(CALLBACK(A, TYPE_PROC_REF(/obj/machinery/power/apc, reset), wire), 300)
		if(WIRE_AI) // Disable AI control for a very short time.
			if(!A.aidisabled)
				A.aidisabled = TRUE
				addtimer(CALLBACK(A, TYPE_PROC_REF(/obj/machinery/power/apc, reset), wire), 10)


/datum/wires/apc/on_cut(index, mend, mob/user)
	var/obj/machinery/power/apc/A = holder
	var/charge_percent = clamp(round(A.cell?.percent()), 0, 100)
	switch(index)
		if(WIRE_POWER1, WIRE_POWER2) // Short out.
			if(mend && !is_cut(WIRE_POWER1) && !is_cut(WIRE_POWER2))
				A.shorted = FALSE
				A.shock(usr, charge_percent)
				if(user?.client)
					var/datum/personal_statistics/personal_statistics = GLOB.personal_statistics_list[user.ckey]
					personal_statistics.apcs_repaired++
			else
				A.shorted = TRUE
				A.shock(usr, charge_percent)
		if(WIRE_AI) // Disable AI control.
			if(mend)
				A.aidisabled = FALSE
			else
				A.aidisabled = TRUE
