## 시청 지역 정보와 시장 매매 흐름을 연결한다.
extends Control

const REGION_BACKGROUNDS := {
	"seoul": preload("res://assets/city_hall_seoul_bg.png"),
	"incheon": preload("res://assets/city_hall_incheon_bg.png"),
	"suwon": preload("res://assets/city_hall_suwon_bg.png"),
	"cheonan": preload("res://assets/city_hall_cheonan_bg.png"),
}
const PRODUCT_ICON_ATLAS := preload("res://assets/product_icon_atlas.png")
const PRODUCT_ICON_CELLS := {
	"seafood": Vector2i(0, 0), "rice": Vector2i(1, 0), "fruit": Vector2i(2, 0),
	"textile": Vector2i(0, 1), "daily_goods": Vector2i(1, 1), "electronics": Vector2i(2, 1),
}

var selected_market_id := ""
var selected_product_id := ""
var selected_side := "buy"
var selected_person_id := "player"
var region_id := "seoul"
var pending_order_id := ""
var order_confirmed := false
var transfer_confirmed := false
@onready var market_list: GridContainer = $Margin/Columns/Body/Markets/Content/MarketScroll/MarketList
@onready var product_list: GridContainer = $Margin/Columns/Body/Products/Content/ProductScroll/ProductList
@onready var direction: OptionButton = $Margin/Columns/Body/Order/Content/Direction
@onready var owner_selector: OptionButton = $Margin/Columns/Body/Order/Content/Owner
@onready var quantity: SpinBox = $Margin/Columns/Body/Order/Content/Quantity
@onready var quote_label: Label = $Margin/Columns/Body/Order/Content/Quote
@onready var result_label: Label = $Margin/Columns/Body/Order/Content/Result
@onready var markets_panel: PanelContainer = $Margin/Columns/Body/Markets
@onready var products_panel: PanelContainer = $Margin/Columns/Body/Products
@onready var order_panel: PanelContainer = $Margin/Columns/Body/Order
@onready var flow_label: Label = $Margin/Columns/Header/HeaderRows/Flow

func _ready() -> void:
	region_id = GameSession.current_region
	var region: Dictionary = GameSession.region_definitions.get(region_id, {})
	var region_name := str(region.get("name", region_id))
	$Backdrop.texture = REGION_BACKGROUNDS.get(region_id, REGION_BACKGROUNDS["seoul"])
	$Margin/Columns/Header/HeaderRows/Title.text = "%s 시청" % region_name
	$Margin/Columns/Header/HeaderRows/RegionInfo.text = "%s  ·  %s" % [region.get("description", "지역 정보"), region.get("industry", "정보 없음")]
	$Margin/Columns/Header/HeaderRows/Accounts.text = _account_summary()
	direction.add_item("구매")
	direction.add_item("판매")
	direction.item_selected.connect(_on_direction_selected)
	_refresh_owner_selector()
	owner_selector.item_selected.connect(_on_owner_selected)
	quantity.value_changed.connect(_on_quantity_changed)
	$Margin/Columns/Body/Order/Content/TradeActions/Confirm.pressed.connect(_confirm_order)
	$Margin/Columns/Body/Order/Content/TradeActions/Cancel.pressed.connect(_cancel_order)
	$Margin/Columns/Body/Order/Content/CargoActions/Transfer.pressed.connect(_transfer_goods)
	$Margin/Columns/Body/Order/Content/CargoActions/Cache.pressed.connect(_store_or_recover_cargo)
	$Margin/Columns/Footer/Workshop.pressed.connect(SceneRouter.enter_mahjong)
	$Margin/Columns/Footer/Exit.pressed.connect(SceneRouter.exit_building)
	_build_market_list()
	_sync_flow()
	GameSession.state_changed.connect(_refresh)

func _build_market_list() -> void:
	for child in market_list.get_children():
		child.queue_free()
	for market in GameSession.get_region_markets(region_id):
		var button := Button.new()
		var first_product: String = str(market["product_ids"][0]) if not market["product_ids"].is_empty() else ""
		button.text = str(market["name"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 112
		if not first_product.is_empty():
			button.icon = _product_icon(first_product)
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_market.bind(str(market["id"])))
		market_list.add_child(button)
	$Margin/Columns/Body/Markets/Content/MarketHint.text = "오늘의 장터 · 시장을 골라보세요"

func _select_market(market_id: String) -> void:
	selected_market_id = market_id
	selected_product_id = ""
	_reset_order()
	for child in product_list.get_children():
		child.queue_free()
	var definition: Dictionary = GameSession.market_definitions[market_id]
	for product_id in definition["product_ids"]:
		var button := Button.new()
		button.set_meta("product_id", str(product_id))
		button.text = "%s · 재고 %d" % [GameSession.get_product_name(product_id), GameSession.get_market_stock(market_id, product_id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 86
		button.icon = _product_icon(str(product_id))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_product.bind(str(product_id)))
		product_list.add_child(button)
	$Margin/Columns/Body/Products/Content/ProductHint.text = "%s 상품" % definition["name"]
	result_label.text = "상품을 골라주세요."
	_sync_flow()

func _select_product(product_id: String) -> void:
	selected_product_id = product_id
	_reset_order()
	_update_quote()
	_sync_flow()

func _on_direction_selected(index: int) -> void:
	selected_side = "buy" if index == 0 else "sell"
	_reset_order()
	_update_quote()

func _on_owner_selected(index: int) -> void:
	selected_person_id = str(owner_selector.get_item_metadata(index))
	_reset_order()
	_update_quote()


## 동행 인물과 활성 차량만 현재 시장의 적재 대상으로 노출한다.
func _refresh_owner_selector() -> void:
	var previous := selected_person_id
	owner_selector.clear()
	for person_id in GameSession.party_ids:
		owner_selector.add_item("주인공" if person_id == "player" else "직원 1")
		owner_selector.set_item_metadata(owner_selector.get_item_count() - 1, str(person_id))
	if not GameSession.active_vehicle_id.is_empty():
		var vehicle: Dictionary = GameSession.vehicle_definitions[GameSession.active_vehicle_id]
		owner_selector.add_item("차량 · %s" % vehicle["name"])
		owner_selector.set_item_metadata(owner_selector.get_item_count() - 1, "vehicle:" + GameSession.active_vehicle_id)
	for index in owner_selector.get_item_count():
		if str(owner_selector.get_item_metadata(index)) == previous:
			owner_selector.select(index)
			selected_person_id = previous
			return
	owner_selector.select(0)
	selected_person_id = str(owner_selector.get_item_metadata(0))

func _on_quantity_changed(_value: float) -> void:
	_reset_order()
	_update_quote()

func _reset_order() -> void:
	pending_order_id = "order-%s" % Time.get_ticks_usec()
	order_confirmed = false
	transfer_confirmed = false
	$Margin/Columns/Body/Order/Content/TradeActions/Confirm.disabled = false
	$Margin/Columns/Body/Order/Content/CargoActions/Transfer.disabled = false

func _update_quote(_value: float = 0.0) -> void:
	if selected_market_id.is_empty() or selected_product_id.is_empty():
		quote_label.text = "시장과 상품을 골라주세요."
		return
	var count := int(quantity.value)
	var quote := GameSession.get_quote(selected_market_id, selected_product_id, selected_side, count)
	if not quote["ok"]:
		quote_label.text = _reason_text(str(quote.get("reason", "invalid_order")))
		return
	var item: Dictionary = GameSession.products[selected_product_id]
	var holding := GameSession.get_inventory_count(selected_person_id, selected_product_id)
	var capacity_g := GameSession._cargo_capacity_g(selected_person_id)
	var current_weight_g := GameSession.get_inventory_weight_g(selected_person_id)
	var action_name := "매입" if selected_side == "buy" else "매도"
	quote_label.text = "%s · %s\n평균 %s원  |  합계 %s원\n주문 %skg  |  보유 %d개\n적재 %s/%skg  |  법인 잔액 %s원" % [item["name"], action_name, _format_number(quote["unit_price"]), _format_number(quote["total"]), str(float(quote["total_weight_g"]) / 1000.0), holding, str(float(current_weight_g) / 1000.0), str(float(capacity_g) / 1000.0), _format_number(GameSession.accounts["corporate"])]

func _confirm_order() -> void:
	if selected_market_id.is_empty() or selected_product_id.is_empty() or order_confirmed:
		return
	var result := GameSession.execute_trade(pending_order_id, selected_market_id, selected_product_id, selected_side, selected_person_id, int(quantity.value))
	if result["ok"]:
		order_confirmed = true
		$Margin/Columns/Body/Order/Content/TradeActions/Confirm.disabled = true
		var profit_text := " · 실현손익 %s원" % _format_number(result["realized_profit"]) if selected_side == "sell" else ""
		result_label.text = "%s 완료 · %s원 · %skg%s" % ["매입" if selected_side == "buy" else "매도", _format_number(result["total"]), str(float(result["weight_g"]) / 1000.0), profit_text]
	else:
		result_label.text = _reason_text(str(result.get("reason", "invalid_order")))
	_update_quote()
	_refresh()

func _cancel_order() -> void:
	GameSession.cancel_trade(pending_order_id)
	order_confirmed = true
	$Margin/Columns/Body/Order/Content/TradeActions/Confirm.disabled = true
	result_label.text = "주문을 취소했습니다."
	_update_quote()

func _transfer_goods() -> void:
	if selected_product_id.is_empty() or transfer_confirmed:
		result_label.text = "이전할 상품과 적재 대상을 선택하세요."
		return
	var other_id := ""
	if selected_person_id.begins_with("vehicle:"):
		other_id = "player"
	elif selected_person_id == "player" and GameSession.party_ids.has("staff_01"):
		other_id = "staff_01"
	elif not GameSession.active_vehicle_id.is_empty():
		other_id = "vehicle:" + GameSession.active_vehicle_id
	if other_id.is_empty():
		result_label.text = "이전할 다른 동행 인물이나 활성 차량이 없습니다."
		return
	var result := GameSession.transfer_goods(selected_person_id, other_id, selected_product_id, int(quantity.value))
	result_label.text = "화물을 옮겼습니다." if result["ok"] else _reason_text(str(result.get("reason", "invalid_transfer")))
	if result["ok"]:
		transfer_confirmed = true
		$Margin/Columns/Body/Order/Content/CargoActions/Transfer.disabled = true
	_update_quote()


## 현재 출입구 위치의 임시 보관 화물을 무료 이동 없이 맡기거나 회수한다.
func _store_or_recover_cargo() -> void:
	if selected_product_id.is_empty():
		result_label.text = "먼저 상품을 선택하세요."
		return
	var position := GameSession.player_position
	var cached := GameSession.get_cargo_cache_count(region_id, position, selected_product_id)
	var store := cached <= 0
	var count := int(quantity.value)
	if not store:
		count = mini(count, cached)
	var result: Dictionary = GameSession.transfer_cargo_cache(selected_person_id, selected_product_id, count, region_id, position, store)
	if result.ok:
		result_label.text = "현지에 %d개 맡겼습니다." % count if store else "현지에서 %d개 찾았습니다." % count
	else:
		result_label.text = _reason_text(str(result.get("reason", "invalid_transfer")))
	_refresh()

func _refresh() -> void:
	$Margin/Columns/Header/HeaderRows/Accounts.text = _account_summary()
	_refresh_owner_selector()
	if not selected_product_id.is_empty():
		var cached := GameSession.get_cargo_cache_count(region_id, GameSession.player_position, selected_product_id)
		$Margin/Columns/Body/Order/Content/CargoActions/Cache.text = "현지 임시 화물 회수 (%d)" % cached if cached > 0 else "현지 임시 보관"
	for button in product_list.get_children():
		var product_id := str(button.get_meta("product_id", ""))
		button.text = "%s · 재고 %d" % [GameSession.get_product_name(product_id), GameSession.get_market_stock(selected_market_id, product_id)]
	if not selected_product_id.is_empty():
		_update_quote()


## 시장→상품→주문이 순서대로 드러나도록 빈 단계를 접는다.
func _sync_flow() -> void:
	markets_panel.visible = true
	products_panel.visible = not selected_market_id.is_empty()
	order_panel.visible = not selected_product_id.is_empty()
	markets_panel.size_flags_stretch_ratio = 1.0 if selected_market_id.is_empty() else 0.9
	products_panel.size_flags_stretch_ratio = 1.1
	order_panel.size_flags_stretch_ratio = 1.3
	if selected_product_id.is_empty():
		flow_label.text = "장터 둘러보기  ›  시장 선택" if selected_market_id.is_empty() else "장터 둘러보기  ›  %s  ›  상품 선택" % GameSession.market_definitions.get(selected_market_id, {}).get("name", "시장")
	else:
		flow_label.text = "장터 둘러보기  ›  %s  ›  %s 주문" % [GameSession.market_definitions.get(selected_market_id, {}).get("name", "시장"), GameSession.get_product_name(selected_product_id)]


## 3×2 상품 삽화표에서 작은 시장 아이콘을 만든다.
func _product_icon(product_id: String) -> Texture2D:
	var cell: Vector2i = PRODUCT_ICON_CELLS.get(product_id, Vector2i.ZERO)
	var atlas := AtlasTexture.new()
	atlas.atlas = PRODUCT_ICON_ATLAS
	atlas.region = Rect2(cell.x * 512, cell.y * 512, 512, 512)
	return atlas

func _account_summary() -> String:
	return "개인 %s원  ·  법인 %s원" % [_format_number(GameSession.accounts["personal"]), _format_number(GameSession.accounts["corporate"])]

func _reason_text(reason: String) -> String:
	match reason:
		"insufficient_stock": return "시장 재고가 부족합니다."
		"insufficient_funds": return "법인 계좌 잔액이 부족합니다."
		"capacity_exceeded": return "적재 한도를 넘었습니다."
		"insufficient_goods": return "보유 수량이 부족합니다."
		"not_traded": return "이 시장에서 취급하지 않는 상품입니다."
		"duplicate_order": return "이미 처리한 주문입니다."
		"invalid_inventory": return "화물 정보를 확인할 수 없습니다. 저장 상태를 확인해주세요."
		"save_failed": return "저장하지 못해 주문을 취소했습니다."
		"invalid_owner": return "이 적재 대상은 현재 이용할 수 없습니다."
		"captivity_locked": return "현재 자산을 옮길 수 없습니다."
		_: return "수량과 적재 대상을 확인해주세요."

func _format_number(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return digits + grouped
