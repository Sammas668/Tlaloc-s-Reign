# GameScreen.gd
# Godot 4.x
# Project path: res://Scripts/ui/GameScreen.gd
#
# Shared game shell:
# - Estate keeps the top Veintena calendar.
# - Other bottom-bar screens use the top row as local focus buttons.
# - Storehouse loads a dedicated StorehouseView scene into ContentRoot.
# - Market loads a dedicated MarketView scene into ContentRoot.
# - The right panel becomes a clickable goods ledger on Storehouse and Market.
extends Control

const STOREHOUSE_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/StorehouseView.tscn")
const STOCKPILE_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/StockpileLedgerRow.tscn")
const MARKET_VIEW_SCENE: PackedScene = preload("res://Scenes/Screens/MarketView.tscn")
const MARKET_LEDGER_ROW_SCENE: PackedScene = preload("res://Scenes/UI/MarketLedgerRow.tscn")

@export var estate_art: Texture2D
@export var fields_art: Texture2D
@export var storehouse_art: Texture2D
@export var workshops_art: Texture2D
@export var shrines_art: Texture2D
@export var warriors_art: Texture2D
@export var market_art: Texture2D
@export var palace_art: Texture2D
@export var rivals_art: Texture2D

@export var visible_veintenas: int = 7

@onready var top_row: HBoxContainer = get_node_or_null(^"SafeArea/MainVBox/CalendarPanel/Margin/CardRow") as HBoxContainer
@onready var location_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/LocationTitle") as Label
@onready var location_art: TextureRect = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/LocationArt") as TextureRect
@onready var content_root: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot") as VBoxContainer
@onready var content_text: RichTextLabel = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/ContentText") as RichTextLabel
@onready var dynamic_view_host: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView/Margin/MainStack/ArtArea/ContentRoot/DynamicViewHost") as VBoxContainer
@onready var notification_title: Label = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationTitle") as Label
@onready var notification_list: VBoxContainer = get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel/Margin/NotificationStack/NotificationScroll/NotificationList") as VBoxContainer

@onready var estate_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/EstateButton") as Button
@onready var fields_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/FieldsButton") as Button
@onready var storehouse_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/StorehouseButton") as Button
@onready var workshops_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WorkshopsButton") as Button
@onready var shrines_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/ShrinesButton") as Button
@onready var warriors_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/WarriorsButton") as Button
@onready var market_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/MarketButton") as Button
@onready var palace_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/PalaceButton") as Button
@onready var rivals_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/RivalsButton") as Button
@onready var advance_turn_button: Button = get_node_or_null(^"SafeArea/MainVBox/BottomNav/Margin/ButtonRow/AdvanceTurnButton") as Button

var current_veintena: int = 1
var current_location_id: String = "estate"
var current_focus_by_location: Dictionary = {}
var selected_storehouse_good_id: String = ""
var selected_market_good_id: String = ""
var storehouse_view: Control = null
var market_view: Control = null

var _veintenas: Array[Dictionary] = [
	{"name": "Atlcahualo", "type": "Rain", "detail": "Opening rains", "tooltip": "Opening rain signs and early Tlaloc pressure."},
	{"name": "Tlacaxipehualiztli", "type": "War", "detail": "War rites", "tooltip": "War rites, martial display and warrior preparation."},
	{"name": "Tozoztontli", "type": "Maize", "detail": "Fields", "tooltip": "Field labour, early maize stores and agricultural vigilance."},
	{"name": "Huey Tozoztli", "type": "Maize", "detail": "Great vigil", "tooltip": "Great agricultural vigil and major maize pressure."},
	{"name": "Toxcatl", "type": "Ritual", "detail": "Offering", "tooltip": "Ritual pressure, offerings and divine favour."},
	{"name": "Etzalcualiztli", "type": "Rain", "detail": "Tlaloc", "tooltip": "Tlaloc, water, rain and food-security pressure."},
	{"name": "Tecuilhuitontli", "type": "Palace", "detail": "Lords", "tooltip": "Noble status, palace attention and social obligation."},
	{"name": "Huey Tecuilhuitl", "type": "Palace", "detail": "Great lords", "tooltip": "Greater noble display, palace pressure and tribute preparation."},
	{"name": "Tlaxochimaco", "type": "Ritual", "detail": "Flowers", "tooltip": "Flowers, offerings and public ritual display."},
	{"name": "Xocotl Huetzi", "type": "Ritual", "detail": "Festival", "tooltip": "Festival pressure, public prestige and ritual display."},
	{"name": "Ochpaniztli", "type": "Stores", "detail": "Sweeping", "tooltip": "Sweeping, stores, obligations and preparation."},
	{"name": "Teotleco", "type": "Ritual", "detail": "Gods arrive", "tooltip": "The gods arrive; omens and divine pressure are prominent."},
	{"name": "Tepeilhuitl", "type": "Rain", "detail": "Mountains", "tooltip": "Mountains, water, rain and agricultural-risk pressure."},
	{"name": "Quecholli", "type": "War", "detail": "Muster", "tooltip": "Muster, hunting, warriors and military readiness."},
	{"name": "Panquetzaliztli", "type": "War", "detail": "Huitzilopochtli", "tooltip": "Huitzilopochtli, war, captives and martial prestige."},
	{"name": "Atemoztli", "type": "Rain", "detail": "Waters", "tooltip": "Water descent, late rain and drought warning pressure."},
	{"name": "Tititl", "type": "Warning", "detail": "Year-end", "tooltip": "Late-year strain, unresolved obligations and warning signs."},
	{"name": "Izcalli", "type": "Warning", "detail": "Reckoning", "tooltip": "Final renewal, reckoning and preparation for Nemontemi."}
]

var _screen_profiles: Dictionary = {
	"estate": {
		"title": "Estate Court",
		"top_mode": "calendar",
		"report_title": "House Warnings & Reports",
		"body": "The estate court is the first screen after loading or starting a game. This keeps the Veintena calendar because it is the whole-house planning view.",
		"sections": [
			{"heading": "Estate overview", "lines": ["Use this as the command screen for the noble house.", "The top row shows the upcoming Veintenas in chronological order.", "The right panel summarises warnings from the whole estate.", "Specialist detail belongs in the other bottom-bar screens."]},
			{"heading": "Current placeholder readout", "lines": ["Prestige: placeholder", "Royal favour: placeholder", "Most urgent issue: check Storehouse and Palace", "Next implementation step: connect Storehouse to real GameState stockpiles."]}
		],
		"reports": ["Calendar remains visible on the Estate screen only.", "Use Estate for whole-house planning and turn advancement.", "Warnings from specialist screens should roll up here."]
	},
	"fields": {
		"title": "Estate Fields",
		"report_title": "Field Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Fields Overview", "body": "A summary of food security, farm labour and rain pressure.", "lines": ["Show total agricultural output.", "Show current rain/drought modifier.", "Show whether field tools and labour are sufficient."], "reports": ["Field overview selected.", "Maize should be the first real output connected here."]},
			{"id": "maize", "label": "Maize", "title": "Maize Fields", "body": "Maize is the food and ritual base of the estate.", "lines": ["Stored maize: placeholder", "Expected maize output: placeholder", "Population food demand: placeholder", "Tlaloc pressure: placeholder"], "reports": ["Warn before maize shortage hits upkeep.", "Tlaloc favour should affect this screen first."]},
			{"id": "cacao", "label": "Cacao", "title": "Cacao Gardens", "body": "Cacao supports status, ritual, tribute and high-value trade.", "lines": ["Cacao output: placeholder", "Cacao stored: placeholder", "Main uses: nobles, rituals, palace goods"], "reports": ["Cacao should feel valuable but not universal."]},
			{"id": "cotton", "label": "Cotton", "title": "Cotton Fields", "body": "Cotton feeds the cloth and fine textile chains.", "lines": ["Cotton output: placeholder", "Cotton stored: placeholder", "Linked buildings: Cloth Workshop, Fine Textile House"], "reports": ["Cotton pressure should foreshadow cloth and fine textile bottlenecks."]},
			{"id": "labour", "label": "Labour", "title": "Field Labour", "body": "Farm labour determines whether land actually produces.", "lines": ["Assigned Macehualtin: placeholder", "Assigned Tlacotin: placeholder", "Unstaffed fields: placeholder"], "reports": ["Field labour should compete with construction, workshops and war preparation."]},
			{"id": "rain", "label": "Rain", "title": "Rain & Tlaloc Pressure", "body": "Rain makes farming sacred as well as economic.", "lines": ["Rain outlook: uncertain", "Tlaloc favour: placeholder", "Drought risk: placeholder"], "reports": ["Rain pressure belongs here and in the Estate calendar."]}
		]
	},
	"storehouse": {
		"title": "Storehouse",
		"report_title": "Stockpile Ledger",
		"special_view": "storehouse",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "food", "label": "Food"},
			{"id": "raw", "label": "Raw"},
			{"id": "processed", "label": "Processed"},
			{"id": "luxury", "label": "Luxury"},
			{"id": "special", "label": "Special"}
		]
	},
	"workshops": {
		"title": "Workshops",
		"report_title": "Workshop Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Workshop Overview", "body": "Summary of production buildings and input pressure.", "lines": ["Built workshops: placeholder", "Blocked workshops: placeholder", "Most needed input: placeholder"], "reports": ["Workshops must show inputs, outputs and staffing."]},
			{"id": "tools", "label": "Tools", "title": "Tool Production", "body": "Tools are the hinge good for construction and production.", "lines": ["Wood input: placeholder", "Tool output: placeholder", "Tool reserve: placeholder"], "reports": ["Tool shortage can paralyse expansion."]},
			{"id": "cloth", "label": "Cloth", "title": "Cloth Production", "body": "Cloth connects cotton, upkeep, construction and palace goods.", "lines": ["Cotton input: placeholder", "Cloth output: placeholder", "Cloth pressure: placeholder"], "reports": ["Cloth is a broad bottleneck."]},
			{"id": "weapons", "label": "Weapons", "title": "Weapon Yard", "body": "Weapons turn obsidian, wood and cloth into Flower Wars readiness.", "lines": ["Weapon output: placeholder", "Inputs: obsidian, wood, cloth, tools", "War readiness link: placeholder"], "reports": ["Weapons are expensive and should stay war-linked."]},
			{"id": "luxury", "label": "Luxury", "title": "Luxury Goods", "body": "Ritual goods and fine textiles support religion, palace and prestige.", "lines": ["Ritual goods: placeholder", "Fine textiles: placeholder", "Palace pressure: placeholder"], "reports": ["Luxury goods should remain high-value and scarce."]}
		]
	},
	"shrines": {
		"title": "Shrines of the Four Gods",
		"report_title": "Omens & Priest Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Shrine Overview", "body": "Summary of divine favour and offering pressure.", "lines": ["Tlaloc: placeholder", "Huitzilopochtli: placeholder", "Tezcatlipoca: placeholder", "Quetzalcoatl: placeholder"], "reports": ["Offerings to one god mean neglecting another."]},
			{"id": "tlaloc", "label": "Tlaloc", "title": "Tlaloc Shrine", "body": "Tlaloc governs rain, maize and drought pressure.", "lines": ["Favour: placeholder", "Rain outlook: placeholder", "Maize risk: placeholder"], "reports": ["Tlaloc pressure should be most visible through farming."]},
			{"id": "huitzilopochtli", "label": "Huitzilopochtli", "title": "Huitzilopochtli Shrine", "body": "Huitzilopochtli governs war, captives and martial prestige.", "lines": ["Favour: placeholder", "Captives: placeholder", "War momentum: placeholder"], "reports": ["War success should feed religious value through captives."]},
			{"id": "tezcatlipoca", "label": "Tezcatlipoca", "title": "Tezcatlipoca Shrine", "body": "Tezcatlipoca governs power, danger, rivalry and political uncertainty.", "lines": ["Favour: placeholder", "Rival pressure: placeholder", "Risk events: placeholder"], "reports": ["This god should feel dangerous rather than simply beneficial."]},
			{"id": "quetzalcoatl", "label": "Quetzalcoatl", "title": "Quetzalcoatl Shrine", "body": "Quetzalcoatl governs legitimacy, order and recognition.", "lines": ["Favour: placeholder", "Stability link: placeholder", "Recognition link: placeholder"], "reports": ["Quetzalcoatl supports the civil face of authority."]},
			{"id": "offerings", "label": "Offerings", "title": "Offerings", "body": "Offerings transform maize, goods and captives into divine favour.", "lines": ["Maize offering: placeholder", "Goods offering: placeholder", "Captive sacrifice: placeholder"], "reports": ["Offering costs must compete with food, palace, war and construction."]}
		]
	},
	"warriors": {
		"title": "Warrior House",
		"report_title": "Warrior Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Warrior Overview", "body": "Summary of military readiness and war risk.", "lines": ["Warrior count: placeholder", "Weapons available: placeholder", "Readiness: placeholder"], "reports": ["War should be tempting, expensive and risky."]},
			{"id": "warriors", "label": "Warriors", "title": "Warrior Capacity", "body": "Warriors require food, support, weapons and training.", "lines": ["Yaotequihuaqueh supported: placeholder", "Warrior House capacity: placeholder", "Warrior upkeep: placeholder"], "reports": ["Warriors are a costly population group, not free power."]},
			{"id": "weapons", "label": "Weapons", "title": "Weapons & Armour", "body": "Weapons and armour connect workshops to Flower Wars readiness.", "lines": ["Weapons: placeholder", "Armour: placeholder", "Replacement need: placeholder"], "reports": ["Equipment shortages should block or weaken war commitments."]},
			{"id": "flower_wars", "label": "Flower Wars", "title": "Flower Wars Commitment", "body": "Commit prepared warriors for captives, looted goods and prestige.", "lines": ["Available opportunity: placeholder", "Expected captives: placeholder", "Loss risk: placeholder"], "reports": ["Flower Wars should resolve strategically, not tactically."]},
			{"id": "returns", "label": "Returns", "title": "Captives, Loot & Losses", "body": "War returns feed the economy, religion and prestige race.", "lines": ["Captives gained: placeholder", "Looted goods: placeholder", "Warrior losses: placeholder"], "reports": ["Loot is secondary; captives remain the unique war output."]}
		]
	},

	"market": {
		"title": "Marketplace",
		"report_title": "Market Ledger",
		"special_view": "market",
		"focuses": [
			{"id": "overview", "label": "Overview"},
			{"id": "prices", "label": "Prices"},
			{"id": "buy", "label": "Buy"},
			{"id": "sell", "label": "Sell"},
			{"id": "rivals", "label": "Rivals"},
			{"id": "reports", "label": "Reports", "title": "Market Reports", "body": "Market reports summarise scarcity, rival procurement and trade pressure without opening a specific good.", "lines": ["Weapons and fine textiles are in crisis in the placeholder data.", "The War Rival should pressure weapons, obsidian and martial goods.", "The Cunning Rival should create market-control pressure through practical bottlenecks.", "The Diplomatic Rival should pressure fine textiles, cacao and tribute goods."], "reports": ["Report focus selected.", "Use reports for market summaries rather than individual good detail.", "Later this can display turn-by-turn market movement and rival procurement notices."]}
		]
	},
	"palace": {
		"title": "Palace Obligations",
		"report_title": "Palace Messages",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Palace Overview", "body": "Summary of political standing and current obligation.", "lines": ["Royal favour: placeholder", "Prestige from palace service: placeholder", "Current demand: placeholder"], "reports": ["The palace should feel distant but consequential."]},
			{"id": "demand", "label": "Demand", "title": "Current Palace Demand", "body": "The ruler names desired goods that compete with local needs.", "lines": ["Desired raw good: placeholder", "Desired processed good: placeholder", "Desired luxury/special good: placeholder"], "reports": ["Demands should be predictable enough to plan around."]},
			{"id": "tribute", "label": "Tribute", "title": "Tribute Delivery", "body": "Tribute proves that the house is useful to the ruler.", "lines": ["Goods reserved for tribute: placeholder", "Delivery value: placeholder", "Failure risk: placeholder"], "reports": ["Tribute should cost enough to create opportunity cost."]},
			{"id": "favour", "label": "Royal Favour", "title": "Royal Favour", "body": "Royal favour measures political acceptance from above.", "lines": ["Current favour: placeholder", "Recent change: placeholder", "Main risk: placeholder"], "reports": ["Royal favour should support recognition, not become spendable currency."]},
			{"id": "recognition", "label": "Recognition", "title": "Recognition", "body": "Recognition is the long-term claim to become the leading lordly house.", "lines": ["Player claim: placeholder", "Rival claim: placeholder", "Palace judgement: placeholder"], "reports": ["Victory should be recognition, not conquest."]}
		]
	},
	"rivals": {
		"title": "Rival Houses",
		"report_title": "Rival Reports",
		"focuses": [
			{"id": "overview", "label": "Overview", "title": "Rival Overview", "body": "Compare all rival houses against the player.", "lines": ["Player prestige: placeholder", "War Rival prestige: placeholder", "Cunning Rival prestige: placeholder", "Diplomatic Rival prestige: placeholder"], "reports": ["Rivals should not be decorative score entries."]},
			{"id": "war", "label": "War Rival", "title": "War Rival — Huitzilopochtli", "body": "The War Rival focuses on weapons, captives, Flower Wars and martial prestige.", "lines": ["Likely first build: Weapon Yard", "Primary hoards: obsidian, weapons, captives", "Procurement style: aggressive"], "reports": ["Watch obsidian, weapons and warrior capacity."]},
			{"id": "cunning", "label": "Cunning Rival", "title": "Cunning Rival — Tezcatlipoca", "body": "The Cunning Rival focuses on market leverage, tools, cloth and hidden pressure.", "lines": ["Likely first build: Storehouse / Market Storage", "Primary hoards: tools, cloth, cacao", "Procurement style: opportunistic"], "reports": ["Watch practical bottlenecks and suspicious market behaviour."]},
			{"id": "diplomatic", "label": "Diplomatic Rival", "title": "Diplomatic Rival — Quetzalcoatl", "body": "The Diplomatic Rival focuses on fine textiles, cacao, tribute goods and legitimacy.", "lines": ["Likely first build: Fine Textile House", "Primary hoards: fine textiles and cacao", "Procurement style: steady"], "reports": ["Watch palace-facing goods and status production."]},
			{"id": "prestige", "label": "Prestige", "title": "Prestige Race", "body": "Prestige makes every system comparative.", "lines": ["Economic prestige: placeholder", "War prestige: placeholder", "Ritual prestige: placeholder", "Palace prestige: placeholder"], "reports": ["The player should understand why each rival gained standing."]}
		]
	}
}

var _stockpiles: Array[Dictionary] = [
	{"id": "maize", "name": "Maize", "category": "food", "stored": 120.0, "incoming": 38.0, "outgoing": 29.0, "reserved": 46.0, "pressure": "Comfortable", "uses": ["Feed population", "Offer to Tlaloc", "Hold against drought", "Trade at market", "Deliver as tribute if demanded"], "reserved_breakdown": ["Population upkeep: 29", "Safety reserve: 12", "Planned Tlaloc offering: 5"]},
	{"id": "wood", "name": "Wood", "category": "raw", "stored": 42.0, "incoming": 16.0, "outgoing": 12.0, "reserved": 24.0, "pressure": "Comfortable", "uses": ["Construction", "Tool production", "Shrines and housing", "Market trade"], "reserved_breakdown": ["Basic tool workshop input: 10", "Commoner housing reserve: 14"]},
	{"id": "cotton", "name": "Cotton", "category": "raw", "stored": 28.0, "incoming": 10.0, "outgoing": 7.0, "reserved": 12.0, "pressure": "Comfortable", "uses": ["Cloth production", "Fine textile production", "Low-status upkeep", "Trade"], "reserved_breakdown": ["Cloth workshop reserve: 10", "Safety reserve: 2"]},
	{"id": "cacao", "name": "Cacao", "category": "raw", "stored": 6.0, "incoming": 2.0, "outgoing": 3.0, "reserved": 5.0, "pressure": "Tight", "uses": ["Noble upkeep", "Ritual goods", "Fine textiles", "Palace tribute", "High-value barter"], "reserved_breakdown": ["Noble support: 2", "Ritual plan: 1", "Palace reserve: 2"]},
	{"id": "obsidian", "name": "Obsidian", "category": "raw", "stored": 14.0, "incoming": 4.0, "outgoing": 3.0, "reserved": 8.0, "pressure": "Comfortable", "uses": ["Weapons", "High-value trade", "War Rival pressure"], "reserved_breakdown": ["Future weapon yard input: 8"]},
	{"id": "cloth", "name": "Cloth", "category": "processed", "stored": 12.0, "incoming": 4.0, "outgoing": 7.0, "reserved": 11.0, "pressure": "Tight", "uses": ["Population upkeep", "Construction", "Weapons", "Noble support", "Palace goods"], "reserved_breakdown": ["Status upkeep: 4", "Construction reserve: 5", "Weapon input reserve: 2"]},
	{"id": "tools", "name": "Tools", "category": "processed", "stored": 9.0, "incoming": 8.0, "outgoing": 5.0, "reserved": 7.0, "pressure": "Comfortable", "uses": ["Building operation", "Construction", "Production chains", "Market leverage"], "reserved_breakdown": ["Field/tool upkeep: 2", "Construction reserve: 5"]},
	{"id": "weapons", "name": "Weapons", "category": "processed", "stored": 2.0, "incoming": 0.0, "outgoing": 1.0, "reserved": 2.0, "pressure": "Crisis", "uses": ["Warrior support", "Flower Wars", "Captive holding", "War prestige"], "reserved_breakdown": ["Warrior House reserve: 1", "Captive holding security: 1"]},
	{"id": "ritual_goods", "name": "Ritual Goods", "category": "luxury", "stored": 4.0, "incoming": 1.0, "outgoing": 2.0, "reserved": 3.0, "pressure": "Tight", "uses": ["Shrine upkeep", "Offerings", "Priest support", "Palace display"], "reserved_breakdown": ["Priest House support: 1", "Offering reserve: 2"]},
	{"id": "fine_textiles", "name": "Fine Textiles", "category": "luxury", "stored": 0.0, "incoming": 0.0, "outgoing": 1.0, "reserved": 0.0, "pressure": "Crisis", "uses": ["Palace demands", "Noble residence", "Prestige", "High-value barter"], "reserved_breakdown": ["No reserve available"]},
	{"id": "captives", "name": "Captives", "category": "special", "stored": 0.0, "incoming": 0.0, "outgoing": 0.0, "reserved": 0.0, "pressure": "Absent", "uses": ["Sacrifice", "Prestige", "Palace opportunities", "Future systems"], "reserved_breakdown": ["None"]},
	{"id": "looted_goods", "name": "Looted Goods", "category": "special", "stored": 0.0, "incoming": 0.0, "outgoing": 0.0, "reserved": 0.0, "pressure": "Absent", "uses": ["Estate development", "Ritual spending", "Worker rewards", "Weapon replacement", "Palace obligations"], "reserved_breakdown": ["None"]}
]

var _market_goods: Array[Dictionary] = [
	{"id": "maize", "name": "Maize", "category": "food", "market_stock": 360.0, "demand": 98.0, "base_value": 1.0, "current_value": 0.81, "coverage": 3.69, "label": "Comfortable", "trend": "Stable", "buy_note": "Safe emergency food purchase if the estate is short.", "sell_note": "Low-profit sale unless the estate has true surplus.", "rival_note": "All houses watch maize during drought or population pressure."},
	{"id": "wood", "name": "Wood", "category": "raw", "market_stock": 200.0, "demand": 35.0, "base_value": 2.0, "current_value": 1.50, "coverage": 5.71, "label": "Abundant", "trend": "Soft", "buy_note": "Useful for construction and tools.", "sell_note": "Poor sale value while abundant.", "rival_note": "Cunning and Diplomatic houses buy wood for early building chains."},
	{"id": "cotton", "name": "Cotton", "category": "raw", "market_stock": 145.0, "demand": 35.0, "base_value": 2.0, "current_value": 1.50, "coverage": 4.16, "label": "Comfortable", "trend": "Stable", "buy_note": "Feeds cloth and fine textile chains.", "sell_note": "Useful sale only if the estate does not need cloth soon.", "rival_note": "Diplomatic Rival wants cotton for fine textiles."},
	{"id": "cloth", "name": "Cloth", "category": "processed", "market_stock": 38.0, "demand": 13.0, "base_value": 5.0, "current_value": 5.08, "coverage": 2.95, "label": "Tight", "trend": "Rising", "buy_note": "Important for upkeep, buildings and palace goods.", "sell_note": "Sell only if it is genuine surplus.", "rival_note": "Cunning Rival can pressure cloth as a practical bottleneck."},
	{"id": "tools", "name": "Tools", "category": "processed", "market_stock": 45.0, "demand": 14.0, "base_value": 7.0, "current_value": 6.54, "coverage": 3.21, "label": "Comfortable", "trend": "Stable", "buy_note": "Tools prevent construction and production paralysis.", "sell_note": "Useful sale only once reserves are safe.", "rival_note": "Cunning Rival hoards and manipulates tool supply."},
	{"id": "obsidian", "name": "Obsidian", "category": "raw", "market_stock": 62.0, "demand": 7.0, "base_value": 8.0, "current_value": 6.00, "coverage": 8.87, "label": "Abundant", "trend": "Soft", "buy_note": "Strategic war-chain input.", "sell_note": "Not high value while abundant, but war demand can change quickly.", "rival_note": "War Rival wants obsidian for weapons."},
	{"id": "weapons", "name": "Weapons", "category": "processed", "market_stock": 0.0, "demand": 4.0, "base_value": 18.0, "current_value": 54.00, "coverage": 0.0, "label": "Crisis", "trend": "Critical", "buy_note": "Buy only for urgent warrior or Flower Wars needs.", "sell_note": "Very profitable if the estate can spare them, but dangerous.", "rival_note": "War Rival aggressively seeks weapons."},
	{"id": "ritual_goods", "name": "Ritual Goods", "category": "luxury", "market_stock": 16.0, "demand": 6.0, "base_value": 12.0, "current_value": 13.47, "coverage": 2.67, "label": "Tight", "trend": "Rising", "buy_note": "Useful for shrines and offerings.", "sell_note": "Good sale if not needed for favour.", "rival_note": "Diplomatic and Cunning houses may pressure ritual supply."},
	{"id": "cacao", "name": "Cacao", "category": "raw", "market_stock": 11.0, "demand": 6.0, "base_value": 15.0, "current_value": 24.57, "coverage": 1.83, "label": "Tight", "trend": "Rising", "buy_note": "Status, ritual and palace-facing good.", "sell_note": "Profitable but politically useful to keep.", "rival_note": "Diplomatic Rival wants cacao for court/status production."},
	{"id": "fine_textiles", "name": "Fine Textiles", "category": "luxury", "market_stock": 0.0, "demand": 2.0, "base_value": 35.0, "current_value": 105.00, "coverage": 0.0, "label": "Crisis", "trend": "Critical", "buy_note": "Extremely expensive but palace-relevant.", "sell_note": "Highly profitable if produced, but usually needed for recognition.", "rival_note": "Diplomatic Rival should chase fine textiles early."}
]


func _ready() -> void:
	_wire_buttons()
	_apply_style()
	show_location("estate")

func _wire_buttons() -> void:
	if estate_button:
		estate_button.pressed.connect(func() -> void: show_location("estate"))
	if fields_button:
		fields_button.pressed.connect(func() -> void: show_location("fields"))
	if storehouse_button:
		storehouse_button.pressed.connect(func() -> void: show_location("storehouse"))
	if workshops_button:
		workshops_button.pressed.connect(func() -> void: show_location("workshops"))
	if shrines_button:
		shrines_button.pressed.connect(func() -> void: show_location("shrines"))
	if warriors_button:
		warriors_button.pressed.connect(func() -> void: show_location("warriors"))
	if market_button:
		market_button.pressed.connect(func() -> void: show_location("market"))
	if palace_button:
		palace_button.pressed.connect(func() -> void: show_location("palace"))
	if rivals_button:
		rivals_button.pressed.connect(func() -> void: show_location("rivals"))
	if advance_turn_button:
		advance_turn_button.pressed.connect(_on_advance_turn_pressed)

func show_location(location_id: String) -> void:
	current_location_id = location_id
	_ensure_focus_for_location(location_id)
	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()
	_update_button_pressed_state()

func show_focus(location_id: String, focus_id: String) -> void:
	current_location_id = location_id
	current_focus_by_location[location_id] = focus_id
	_refresh_top_area()
	_refresh_main_content()
	_refresh_right_panel()
	_update_button_pressed_state()

func _ensure_focus_for_location(location_id: String) -> void:
	if current_focus_by_location.has(location_id):
		return
	var profile: Dictionary = _profile_for_location(location_id)
	var focuses: Array = profile.get("focuses", []) as Array
	if focuses.size() > 0:
		var first_focus: Dictionary = focuses[0] as Dictionary
		current_focus_by_location[location_id] = String(first_focus.get("id", "overview"))
	else:
		current_focus_by_location[location_id] = "overview"

func _profile_for_location(location_id: String) -> Dictionary:
	if _screen_profiles.has(location_id):
		return _screen_profiles[location_id] as Dictionary
	return _screen_profiles["estate"] as Dictionary

func _current_focus_id() -> String:
	return String(current_focus_by_location.get(current_location_id, "overview"))

func _current_focus_data() -> Dictionary:
	var profile: Dictionary = _profile_for_location(current_location_id)
	var focuses: Array = profile.get("focuses", []) as Array
	var focus_id: String = _current_focus_id()
	for focus_variant: Variant in focuses:
		var focus: Dictionary = focus_variant as Dictionary
		if String(focus.get("id", "")) == focus_id:
			return focus
	if focuses.size() > 0:
		return focuses[0] as Dictionary
	return profile

func _refresh_top_area() -> void:
	if top_row == null:
		return
	for child: Node in top_row.get_children():
		child.queue_free()

	var profile: Dictionary = _profile_for_location(current_location_id)
	var top_mode: String = String(profile.get("top_mode", "focus"))
	if top_mode == "calendar":
		_build_calendar_cards()
	else:
		_build_focus_buttons(profile)

func _build_calendar_cards() -> void:
	if top_row == null:
		return
	var start_index: int = clampi(current_veintena - 1, 0, _veintenas.size() - 1)
	var end_index: int = mini(start_index + visible_veintenas, _veintenas.size())
	for i: int in range(start_index, end_index):
		var data: Dictionary = _veintenas[i] as Dictionary
		var card_data: Dictionary = data.duplicate()
		card_data["number"] = i + 1
		card_data["is_current"] = i == start_index
		top_row.add_child(_make_veintena_card(card_data))

func _make_veintena_card(data: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 94)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = "Veintena " + str(int(data.get("number", 0))) + " — " + String(data.get("name", "")) + ". " + String(data.get("tooltip", ""))

	var style: StyleBoxFlat = _make_panel_style(Color(0.055, 0.08, 0.075, 0.92), Color(0.33, 0.70, 0.62, 0.55), 10)
	if bool(data.get("is_current", false)):
		style = _make_panel_style(Color(0.09, 0.13, 0.115, 0.98), Color(0.76, 0.63, 0.32, 0.85), 10)
	card.add_theme_stylebox_override("panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)

	_stack_label(stack, "Veintena " + str(int(data.get("number", 0))), 13)
	_stack_label(stack, String(data.get("name", "")), 11)
	_stack_label(stack, String(data.get("type", "?")), 13)
	_stack_label(stack, String(data.get("detail", "")), 11)
	return card

func _build_focus_buttons(profile: Dictionary) -> void:
	if top_row == null:
		return
	var focuses: Array = profile.get("focuses", []) as Array
	var focus_id: String = _current_focus_id()
	for focus_variant: Variant in focuses:
		var focus: Dictionary = focus_variant as Dictionary
		var button: Button = Button.new()
		button.text = String(focus.get("label", "Focus"))
		button.toggle_mode = true
		button.button_pressed = String(focus.get("id", "")) == focus_id
		button.custom_minimum_size = Vector2(130, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		var next_focus_id: String = String(focus.get("id", "overview"))
		button.pressed.connect(func() -> void: show_focus(current_location_id, next_focus_id))
		top_row.add_child(button)

func _stack_label(parent: VBoxContainer, text: String, font_size: int) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func _refresh_main_content() -> void:
	var profile: Dictionary = _profile_for_location(current_location_id)
	if location_title:
		location_title.text = String(profile.get("title", "Estate"))
	if location_art:
		location_art.texture = _art_for_location(current_location_id)

	_clear_dynamic_view()
	var special_view: String = String(profile.get("special_view", ""))
	if special_view == "storehouse":
		_show_storehouse_view()
	elif special_view == "market":
		_show_market_view()
	else:
		_show_text_view(profile)

func _show_text_view(profile: Dictionary) -> void:
	if content_root:
		content_root.visible = true
	if content_text == null:
		return
	content_text.visible = true
	content_text.bbcode_enabled = true
	content_text.fit_content = true
	content_text.scroll_active = false
	content_text.text = _build_content_text(profile)

func _build_content_text(profile: Dictionary) -> String:
	var focus: Dictionary = _current_focus_data()
	var title: String = String(focus.get("title", profile.get("title", "")))
	var body: String = String(focus.get("body", profile.get("body", "")))
	var output: String = "[b]" + title + "[/b]\n"
	output += body + "\n\n"
	var lines: Array = focus.get("lines", []) as Array
	for line_variant: Variant in lines:
		output += "• " + String(line_variant) + "\n"

	var sections: Array = profile.get("sections", []) as Array
	for section_variant: Variant in sections:
		var section: Dictionary = section_variant as Dictionary
		output += "\n[b]" + String(section.get("heading", "Section")) + "[/b]\n"
		var section_lines: Array = section.get("lines", []) as Array
		for section_line_variant: Variant in section_lines:
			output += "• " + String(section_line_variant) + "\n"
	return output.strip_edges()

func _show_storehouse_view() -> void:
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	storehouse_view = STOREHOUSE_VIEW_SCENE.instantiate() as Control
	if storehouse_view == null:
		return
	storehouse_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storehouse_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(storehouse_view)
	if storehouse_view.has_signal("good_selected"):
		storehouse_view.connect("good_selected", Callable(self, "_on_storehouse_good_selected"))
	if storehouse_view.has_signal("good_closed"):
		storehouse_view.connect("good_closed", Callable(self, "_on_storehouse_good_closed"))
	if storehouse_view.has_method("setup"):
		storehouse_view.call("setup", _stockpiles, _current_focus_id(), selected_storehouse_good_id)

func _show_market_view() -> void:
	if content_text:
		content_text.visible = false
	if content_root:
		content_root.visible = true
	if dynamic_view_host == null:
		return
	market_view = MARKET_VIEW_SCENE.instantiate() as Control
	if market_view == null:
		return
	market_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dynamic_view_host.add_child(market_view)
	if market_view.has_signal("good_selected"):
		market_view.connect("good_selected", Callable(self, "_on_market_good_selected"))
	if market_view.has_signal("good_closed"):
		market_view.connect("good_closed", Callable(self, "_on_market_good_closed"))
	if market_view.has_method("setup"):
		market_view.call("setup", _market_goods, _current_focus_id(), selected_market_good_id)

func _clear_dynamic_view() -> void:
	storehouse_view = null
	market_view = null
	if dynamic_view_host == null:
		return
	for child: Node in dynamic_view_host.get_children():
		child.queue_free()

func _refresh_right_panel() -> void:
	if notification_list == null:
		return
	for child: Node in notification_list.get_children():
		child.queue_free()

	var profile: Dictionary = _profile_for_location(current_location_id)
	if notification_title:
		notification_title.text = String(profile.get("report_title", "Warnings & Reports"))

	if current_location_id == "storehouse":
		_build_storehouse_ledger()
		return
	if current_location_id == "market" and _current_focus_id() != "reports":
		_build_market_ledger()
		return

	var focus: Dictionary = _current_focus_data()
	var messages: Array = focus.get("reports", profile.get("reports", [])) as Array
	for message_variant: Variant in messages:
		notification_list.add_child(_make_notification_label(String(message_variant)))
	notification_list.add_child(_make_notification_label("Veintena " + str(current_veintena) + " of 18 is active."))

func _build_storehouse_ledger() -> void:
	var focus_id: String = _current_focus_id()
	var goods: Array[Dictionary] = _filtered_stockpiles(focus_id)
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Button = STOCKPILE_LEDGER_ROW_SCENE.instantiate() as Button
		if row == null:
			continue
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_storehouse_good_id)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_storehouse_good_selected"))
		notification_list.add_child(row)

func _filtered_stockpiles(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _stockpiles:
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview":
				include_good = true
			"reserved":
				include_good = float(good.get("reserved", 0.0)) > 0.0
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output


func _build_market_ledger() -> void:
	var focus_id: String = _current_focus_id()
	var goods: Array[Dictionary] = _filtered_market_goods(focus_id)
	for good_variant: Variant in goods:
		var good: Dictionary = good_variant as Dictionary
		var row: Button = MARKET_LEDGER_ROW_SCENE.instantiate() as Button
		if row == null:
			continue
		if row.has_method("set_good_data"):
			row.call("set_good_data", good, String(good.get("id", "")) == selected_market_good_id)
		if row.has_signal("good_selected"):
			row.connect("good_selected", Callable(self, "_on_market_good_selected"))
		notification_list.add_child(row)

func _filtered_market_goods(focus_id: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for good_variant: Variant in _market_goods:
		var good: Dictionary = good_variant as Dictionary
		var category: String = String(good.get("category", ""))
		var include_good: bool = false
		match focus_id:
			"overview", "prices", "buy", "sell", "rivals":
				include_good = true
			_:
				include_good = category == focus_id
		if include_good:
			output.append(good)
	return output

func _on_storehouse_good_selected(good_id: String) -> void:
	if selected_storehouse_good_id == good_id:
		# Already selected. Just keep the ledger highlight in sync.
		_refresh_right_panel()
		return

	selected_storehouse_good_id = good_id
	if storehouse_view != null and storehouse_view.has_method("select_good"):
		storehouse_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_storehouse_good_closed() -> void:
	selected_storehouse_good_id = ""
	_refresh_right_panel()

func _on_market_good_selected(good_id: String) -> void:
	if selected_market_good_id == good_id:
		_refresh_right_panel()
		return

	selected_market_good_id = good_id
	if market_view != null and market_view.has_method("select_good"):
		market_view.call("select_good", good_id)
	_refresh_right_panel()

func _on_market_good_closed() -> void:
	selected_market_good_id = ""
	_refresh_right_panel()

func _make_notification_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = "• " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	return label

func _art_for_location(location_id: String) -> Texture2D:
	match location_id:
		"estate":
			return estate_art
		"fields":
			return fields_art
		"storehouse":
			return storehouse_art
		"workshops":
			return workshops_art
		"shrines":
			return shrines_art
		"warriors":
			return warriors_art
		"market":
			return market_art
		"palace":
			return palace_art
		"rivals":
			return rivals_art
	return null

func _update_button_pressed_state() -> void:
	var button_map: Dictionary = {
		"estate": estate_button,
		"fields": fields_button,
		"storehouse": storehouse_button,
		"workshops": workshops_button,
		"shrines": shrines_button,
		"warriors": warriors_button,
		"market": market_button,
		"palace": palace_button,
		"rivals": rivals_button
	}
	for key_variant: Variant in button_map.keys():
		var key: String = String(key_variant)
		var button: Button = button_map[key] as Button
		if button:
			button.button_pressed = key == current_location_id

func _on_advance_turn_pressed() -> void:
	current_veintena += 1
	if current_veintena > 18:
		current_veintena = 1
	_refresh_top_area()
	_refresh_right_panel()

func _apply_style() -> void:
	var panel_nodes: Array = [
		get_node_or_null(^"SafeArea/MainVBox/CalendarPanel"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/MainView"),
		get_node_or_null(^"SafeArea/MainVBox/MiddleRow/NotificationPanel"),
		get_node_or_null(^"SafeArea/MainVBox/BottomNav")
	]
	for node_variant: Variant in panel_nodes:
		var panel: PanelContainer = node_variant as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.055, 0.052, 0.90), Color(0.34, 0.71, 0.63, 0.45), 14))

	if location_title:
		location_title.add_theme_font_size_override("font_size", 26)
	if content_text:
		content_text.add_theme_font_size_override("normal_font_size", 16)
		content_text.add_theme_font_size_override("bold_font_size", 17)
		# Text on top of illustrated backgrounds needs a dark translucent plate.
		# This especially helps the Estate overview, where white text sits over the main image.
		content_text.add_theme_stylebox_override("normal", _make_text_overlay_style())

	var buttons: Array = [estate_button, fields_button, storehouse_button, workshops_button, shrines_button, warriors_button, market_button, palace_button, rivals_button, advance_turn_button]
	for button_variant: Variant in buttons:
		var button: Button = button_variant as Button
		if button:
			button.custom_minimum_size = Vector2(0, 48)
			button.add_theme_font_size_override("font_size", 15)
			if button != advance_turn_button:
				button.toggle_mode = true

func _make_text_overlay_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# Around 0.55 alpha: dark enough to read, transparent enough to keep the art visible.
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.border_color = Color(0.50, 0.82, 0.74, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 6
	return style

func _make_panel_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style
