# MarketTradeSystem.gd
# Godot 4.x
# Project path: res://Scripts/Systems/MarketTradeSystem.gd
#
# Owns barter-trade pricing, validation and application rules.
# Accepted trades mutate CampaignState stockpiles directly. TRGameState mirror
# dictionaries are no longer used as a fallback source of truth.

class_name MarketTradeSystem
extends RefCounted

const SCHEMA_TRADE_PREVIEW: String = "market_trade_preview_v0_43_2"
const SCHEMA_TRADE_VALIDATION: String = "market_trade_validation_v0_43_2"


func get_trade_preview(state: Node, trade_plan: Dictionary) -> Dictionary:
	var market_goods: Dictionary = market_goods_by_id(state)
	var store_goods: Dictionary = store_goods_by_id(state)
	var validation: Dictionary = validate_trade_plan(state, trade_plan, market_goods, store_goods, false)
	var totals: Dictionary = basket_totals(trade_plan, market_goods, "")
	var sold_value: float = float(totals.get("sold_value", 0.0))
	var bought_value: float = float(totals.get("bought_value", 0.0))
	var balance: float = sold_value - bought_value
	var trade_lines: Array[Dictionary] = prestige_trade_lines(trade_plan, market_goods)

	return {
		"schema_version": SCHEMA_TRADE_PREVIEW,
		"trade_plan": _clean_trade_plan(trade_plan),
		"sold_value": sold_value,
		"bought_value": bought_value,
		"balance": balance,
		"valid": bool(validation.get("valid", false)),
		"reason": String(validation.get("reason", "")),
		"sold_parts": validation.get("sold_parts", []),
		"bought_parts": validation.get("bought_parts", []),
		"trade_lines": trade_lines,
		"summary": trade_summary_text(sold_value, bought_value, balance)
	}


func validate_trade_plan(state: Node, trade_plan: Dictionary, market_goods: Dictionary = {}, store_goods: Dictionary = {}, include_parts: bool = true) -> Dictionary:
	if state == null:
		return {"schema_version": SCHEMA_TRADE_VALIDATION, "valid": false, "reason": "Trade data is not connected."}

	if market_goods.is_empty():
		market_goods = market_goods_by_id(state)
	if store_goods.is_empty():
		store_goods = store_goods_by_id(state)

	var sold_value: float = 0.0
	var bought_value: float = 0.0
	var clean_plan: Dictionary = {}
	var sold_parts: Array[String] = []
	var bought_parts: Array[String] = []

	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(trade_plan[key_variant])
		if absf(amount) <= 0.001:
			continue

		var store_good: Dictionary = store_goods.get(resource_id, {}) as Dictionary
		var market_good: Dictionary = market_goods.get(resource_id, {}) as Dictionary
		var free_value: float = maxf(0.0, float(store_good.get("free", 0.0)))
		var market_stock: float = maxf(0.0, float(market_good.get("market_stock", 0.0)))
		var pricing: Dictionary = trade_pricing(market_goods, resource_id, amount)
		var trade_value: float = float(pricing.get("total_value", 0.0))
		var name: String = good_name(state, resource_id, store_good, market_good)

		if amount < -0.001:
			var sell_amount: float = absf(amount)
			if sell_amount > free_value + 0.001:
				return {"schema_version": SCHEMA_TRADE_VALIDATION, "valid": false, "reason": "Not enough free " + name + " to sell after reserves."}
			sold_value += trade_value
			if include_parts:
				sold_parts.append(name + " " + _fmt(sell_amount) + " value " + _fmt(trade_value))
			clean_plan[resource_id] = -sell_amount
		elif amount > 0.001:
			if amount > market_stock + 0.001:
				return {"schema_version": SCHEMA_TRADE_VALIDATION, "valid": false, "reason": "Not enough " + name + " in the market to buy."}
			bought_value += trade_value
			if include_parts:
				bought_parts.append(name + " " + _fmt(amount) + " value " + _fmt(trade_value))
			clean_plan[resource_id] = amount

	if clean_plan.is_empty():
		return {"schema_version": SCHEMA_TRADE_VALIDATION, "valid": false, "reason": "No barter offer selected."}

	var balance: float = sold_value - bought_value
	if balance < -0.001:
		return {"schema_version": SCHEMA_TRADE_VALIDATION, "valid": false, "reason": "Trade asks for " + _fmt(absf(balance)) + " more value than offered."}

	return {
		"schema_version": SCHEMA_TRADE_VALIDATION,
		"valid": true,
		"reason": "Trade can be accepted.",
		"plan": clean_plan,
		"sold_value": sold_value,
		"bought_value": bought_value,
		"balance": balance,
		"sold_parts": sold_parts,
		"bought_parts": bought_parts,
		"trade_lines": prestige_trade_lines(clean_plan, market_goods)
	}


func apply_trade_plan(state: Node, trade_plan: Dictionary) -> Dictionary:
	var validation: Dictionary = validate_trade_plan(state, trade_plan)
	if not bool(validation.get("valid", false)):
		return validation
	if state == null:
		return {"valid": false, "reason": "Trade data is not connected."}

	var plan: Dictionary = validation.get("plan", {}) as Dictionary
	var campaign_ref: RefCounted = _campaign_stockpile_state(state)

	if campaign_ref == null or not campaign_ref.has_method("add_estate_stock") or not campaign_ref.has_method("add_market_stock"):
		return {"valid": false, "reason": "CampaignState stockpile API is not connected."}

	for key_variant: Variant in plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(plan[key_variant])
		campaign_ref.call("add_estate_stock", resource_id, amount)
		campaign_ref.call("add_market_stock", resource_id, -amount)
	_mirror_stockpile_compatibility(state)

	var report_line: String = accepted_trade_report_line(validation)
	_append_report_line(state, report_line)

	if state.has_signal("state_changed"):
		state.emit_signal("state_changed")

	validation["applied"] = true
	validation["report_line"] = report_line
	return validation


func accepted_trade_report_line(validation: Dictionary) -> String:
	var sold_parts: Array = validation.get("sold_parts", []) as Array
	var bought_parts: Array = validation.get("bought_parts", []) as Array
	var balance: float = float(validation.get("balance", 0.0))
	var report_line: String = "Barter trade accepted."

	if not sold_parts.is_empty():
		report_line += " Sold: " + ", ".join(PackedStringArray(sold_parts)) + "."
	if not bought_parts.is_empty():
		report_line += " Bought: " + ", ".join(PackedStringArray(bought_parts)) + "."
	if balance > 0.001:
		report_line += " Surplus barter value " + _fmt(balance) + " lost."

	return report_line


func basket_totals(trade_plan: Dictionary, market_goods: Dictionary, excluded_resource_id: String = "") -> Dictionary:
	var sold_value: float = 0.0
	var bought_value: float = 0.0

	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		if excluded_resource_id != "" and resource_id == excluded_resource_id:
			continue

		var amount: float = float(trade_plan[key_variant])
		var pricing: Dictionary = trade_pricing(market_goods, resource_id, amount)
		var value: float = float(pricing.get("total_value", 0.0))
		if amount < -0.001:
			sold_value += value
		elif amount > 0.001:
			bought_value += value

	return {"sold_value": sold_value, "bought_value": bought_value, "balance": sold_value - bought_value}


func largest_buy_amount_within_value(market_goods: Dictionary, resource_id: String, target_value: float, max_amount: int) -> int:
	var best_amount: int = 0
	for amount: int in range(1, max_amount + 1):
		var value: float = float(trade_pricing(market_goods, resource_id, float(amount)).get("total_value", 0.0))
		if value <= target_value + 0.001:
			best_amount = amount
		else:
			break
	return best_amount


func smallest_sell_amount_covering_value(market_goods: Dictionary, resource_id: String, target_value: float, max_amount: int) -> int:
	for amount: int in range(1, max_amount + 1):
		var value: float = float(trade_pricing(market_goods, resource_id, -float(amount)).get("total_value", 0.0))
		if value >= target_value - 0.001:
			return amount
	return 0


func prestige_trade_lines(trade_plan: Dictionary, market_goods: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []

	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(trade_plan[key_variant])
		if absf(amount) <= 0.001:
			continue

		var pricing: Dictionary = trade_pricing(market_goods, resource_id, amount)
		output.append({
			"resource_id": resource_id,
			"amount": amount,
			"average_unit_value": float(pricing.get("average_value", 0.0)),
			"total_value": float(pricing.get("total_value", 0.0))
		})

	return output


func trade_pricing(market_goods: Dictionary, resource_id: String, amount: float) -> Dictionary:
	var market_good: Dictionary = market_goods.get(resource_id, {}) as Dictionary
	var start_stock: float = market_stock_for_pricing(market_good)
	var actual_market_stock: float = maxf(0.0, float(market_good.get("market_stock", start_stock)))
	var remaining_amount: int = int(absf(roundf(amount)))
	var working_stock: float = start_stock
	var total_value: float = 0.0
	var first_unit_value: float = trade_price_for_stock(market_goods, resource_id, working_stock)
	var last_paid_unit_value: float = first_unit_value

	if remaining_amount <= 0:
		return {
			"total_value": 0.0,
			"average_value": 0.0,
			"first_unit_value": first_unit_value,
			"last_unit_value": first_unit_value,
			"next_unit_value": first_unit_value,
			"start_stock": start_stock,
			"final_stock": start_stock
		}

	if amount > 0.001:
		remaining_amount = mini(remaining_amount, int(floor(actual_market_stock)))
		for index: int in range(remaining_amount):
			var buy_unit_value: float = trade_price_for_stock(market_goods, resource_id, working_stock)
			total_value += buy_unit_value
			last_paid_unit_value = buy_unit_value
			working_stock = maxf(0.0, working_stock - 1.0)
	elif amount < -0.001:
		for index: int in range(remaining_amount):
			var sell_unit_value: float = trade_price_for_stock(market_goods, resource_id, working_stock)
			total_value += sell_unit_value
			last_paid_unit_value = sell_unit_value
			working_stock += 1.0

	var average_value: float = 0.0
	if remaining_amount > 0:
		average_value = total_value / float(remaining_amount)

	return {
		"total_value": total_value,
		"average_value": average_value,
		"first_unit_value": first_unit_value,
		"last_unit_value": last_paid_unit_value,
		"next_unit_value": trade_price_for_stock(market_goods, resource_id, working_stock),
		"start_stock": start_stock,
		"final_stock": working_stock
	}


func current_unit_value_for(market_goods: Dictionary, resource_id: String) -> float:
	var market_good: Dictionary = market_goods.get(resource_id, {}) as Dictionary
	var pricing_stock: float = market_stock_for_pricing(market_good)
	return trade_price_for_stock(market_goods, resource_id, pricing_stock)


func market_stock_for_pricing(market_good: Dictionary) -> float:
	return maxf(0.0, float(market_good.get("projected_market_stock", market_good.get("market_stock", 0.0))))


func trade_price_for_stock(market_goods: Dictionary, resource_id: String, stock_value: float) -> float:
	var market_good: Dictionary = market_goods.get(resource_id, {}) as Dictionary
	var base_value: float = maxf(0.0, float(market_good.get("base_value", 1.0)))
	var demand_value: float = market_demand_for_pricing(market_good)
	if demand_value <= 0.001:
		return base_value

	var coverage: float = maxf(0.0, stock_value) / demand_value
	return base_value * local_scarcity_multiplier(coverage, demand_value)


func market_demand_for_pricing(market_good: Dictionary) -> float:
	var demand_value: float = maxf(0.0, float(market_good.get("village_total_demand", 0.0)))
	if demand_value <= 0.001:
		demand_value = maxf(0.0, float(market_good.get("demand", 0.0)))
	return demand_value


func local_scarcity_multiplier(coverage: float, demand: float) -> float:
	return MarketPricingRules.scarcity_multiplier(coverage, demand)


func market_goods_by_id(state: Node) -> Dictionary:
	var output: Dictionary = {}
	if state == null or not state.has_method("get_market_goods"):
		return output

	var goods: Array = state.call("get_market_goods") as Array
	for good_variant: Variant in goods:
		if good_variant is Dictionary:
			var good: Dictionary = good_variant as Dictionary
			output[String(good.get("id", ""))] = good

	return output


func store_goods_by_id(state: Node) -> Dictionary:
	var output: Dictionary = {}
	if state == null or not state.has_method("get_storehouse_goods"):
		return output

	var goods: Array = state.call("get_storehouse_goods") as Array
	for good_variant: Variant in goods:
		if good_variant is Dictionary:
			var good: Dictionary = good_variant as Dictionary
			output[String(good.get("id", ""))] = good

	return output


func good_name(state: Node, resource_id: String, store_good: Dictionary, market_good: Dictionary) -> String:
	var name: String = String(store_good.get("name", ""))
	if name != "":
		return name

	name = String(market_good.get("name", ""))
	if name != "":
		return name

	if state != null and state.has_method("get_resource_name"):
		return String(state.call("get_resource_name", resource_id))

	return resource_id.replace("_", " ").capitalize()


func trade_summary_text(sold_value: float, bought_value: float, balance: float) -> String:
	if balance < -0.001:
		return "Offer more goods or buy less to make the barter acceptable."
	if bought_value <= 0.001 and sold_value <= 0.001:
		return "Move a slider to build a barter offer."
	if balance > 0.001:
		return "Surplus value will be lost when accepted."
	return "Balanced barter ready."


func _campaign_stockpile_state(state: Node) -> RefCounted:
	if state == null:
		return null
	if state.has_method("_get_campaign_state"):
		var raw: Variant = state.call("_get_campaign_state")
		if raw is RefCounted:
			return raw as RefCounted
	return null

func _mirror_stockpile_compatibility(state: Node) -> void:
	if state != null and state.has_method("_mirror_stockpile_compatibility_from_campaign_state"):
		state.call("_mirror_stockpile_compatibility_from_campaign_state")


func _append_report_line(state: Node, line: String) -> void:
	if line.strip_edges() == "":
		return

	if state != null and state.has_method("_append_report_line"):
		state.call("_append_report_line", line)
		return

	var runtime_state: RefCounted = null
	if state != null and state.has_method("_get_campaign_state"):
		var runtime: Variant = state.call("_get_campaign_state")
		if runtime is RefCounted:
			runtime_state = runtime as RefCounted

	if runtime_state != null and runtime_state.has_method("append_report_line"):
		runtime_state.call("append_report_line", line)
		if state != null and state.has_method("_mirror_calendar_report_compatibility_from_campaign_state"):
			state.call("_mirror_calendar_report_compatibility_from_campaign_state")
		return

	# No TRGameState mirror fallback here. Reports are CampaignState-owned.


func _clean_trade_plan(trade_plan: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_variant: Variant in trade_plan.keys():
		var resource_id: String = String(key_variant)
		var amount: float = float(trade_plan[key_variant])
		if absf(amount) > 0.001:
			output[resource_id] = amount
	return output


func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value
