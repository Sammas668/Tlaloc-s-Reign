# PalacePresentationRules.gd
# Godot 4.x
# Project path: res://Scripts/Systems/PalacePresentationRules.gd
#
# Extracted static palace/prestige presentation rules from
# GameScreenMarketOverviewPatch.gd. This keeps the active wrapper focused on
# composing UI while stable display names, colours and route flavour live in a
# small reusable rules helper.
class_name PalacePresentationRules
extends RefCounted

static func ordinal_number(value: int) -> String:
	var suffix: String = "th"
	var mod_100: int = value % 100
	if mod_100 < 11 or mod_100 > 13:
		match value % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return str(value) + suffix

static func prestige_source_display_name(source_id: String) -> String:
	match source_id:
		"economic_savvy_trade":
			return "Savvy Trade"
		"court_need_donation":
			return "Court Need Donations"
		"flower_war_attack":
			return "Flower War Musters"
		"flower_war_defence":
			return "Flower War Defence"
		"religion_sacrifice":
			return "Ritual Sacrifice"
		"shrine_level":
			return "Shrine Recognition"
		"palace_recognition":
			return "Palace Recognition"
	return source_id.replace("_", " ").capitalize()

static func prestige_source_colour(source_id: String) -> Color:
	match source_id:
		"economic_savvy_trade":
			return Color(0.50, 0.82, 0.74, 0.90)
		"court_need_donation":
			return Color(0.96, 0.78, 0.42, 0.90)
		"flower_war_attack", "flower_war_defence":
			return Color(0.90, 0.42, 0.30, 0.90)
		"religion_sacrifice":
			return Color(0.70, 0.55, 0.92, 0.90)
		"shrine_level":
			return Color(0.42, 0.70, 0.96, 0.90)
		"palace_recognition":
			return Color(0.95, 0.86, 0.54, 0.90)
	return Color(0.70, 0.74, 0.68, 0.85)

static func prestige_record_time_text(record: Dictionary) -> String:
	var veintena: int = int(record.get("veintena", 0))
	if veintena > 0:
		return "Veintena " + str(veintena)
	return "Current turn"

static func palace_staff_display_name(staff_id: String) -> String:
	match staff_id:
		"tlamacazqueh":
			return "Priests"
		"pipiltin":
			return "Nobles"
		"tlacotin":
			return "Tlacotin"
		"macehualtin":
			return "Macehualtin"
		"tolteca":
			return "Tolteca"
		"yaotequihuaqueh":
			return "Warriors"
		"malli":
			return "Captives"
	return staff_id.replace("_", " ").capitalize()

static func route_colour(god_id: String) -> Color:
	match god_id:
		"tlaloc":
			return Color(0.32, 0.86, 0.92, 0.96)
		"huitzilopochtli":
			return Color(0.92, 0.36, 0.26, 0.96)
		"tezcatlipoca":
			return Color(0.62, 0.48, 0.88, 0.96)
		"quetzalcoatl":
			return Color(0.52, 0.90, 0.58, 0.96)
	return Color(0.72, 0.62, 0.42, 0.94)

static func route_domain_line(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Rain • Drought • Flood • Harvest Signs"
		"huitzilopochtli":
			return "War • Captives • Sacrifice • Martial Authority"
		"tezcatlipoca":
			return "Scarcity • Intrigue • Rival Pressure • Hidden Power"
		"quetzalcoatl":
			return "Legitimacy • Recognition • Tribute Trust • Palace Order"
	return "Divine authority"

static func route_flavour(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "Read the coming pressure of sky, lake and field before rival houses can react."
		"huitzilopochtli":
			return "Formally authorise the house to launch Flower Wars and pursue the war route."
		"tezcatlipoca":
			return "Exploit shortage, fear, ambition and rival weakness through dangerous palace power."
		"quetzalcoatl":
			return "Strengthen the house's credibility before ruler, court and region."
	return "The palace route will define the house's authority."

static func route_seat_glyph(god_id: String) -> String:
	match god_id:
		"tlaloc":
			return "WATER SEAT"
		"huitzilopochtli":
			return "WAR SEAT"
		"tezcatlipoca":
			return "MIRROR SEAT"
		"quetzalcoatl":
			return "FEATHER SEAT"
	return "EMPTY ALTAR"
