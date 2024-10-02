@tool
extends HBoxContainer

class_name LocalAssetsPaginationBar

signal page_changed(new_page: int)

var total_pages: int = 1:  # Adjust this to the number of total pages
	set(v):
		total_pages = v
		_draw_pagination()
var current_page: int = 1
var max_visible_buttons: int = 10  # Maximum number of visible buttons
var button_width: int = 40


func _ready():
	_draw_pagination()


func _draw_pagination():
	clear()  # Remove all existing buttons before redrawing
	# First and Previous Buttons
	_create_nav_button("First", 1, current_page > 1)
	_create_nav_button("Previous", current_page - 1, current_page > 1)

	# Page Buttons
	var start_page = max(1, current_page - 5)
	var end_page = min(total_pages, start_page + max_visible_buttons - 1)

	# Adjust page buttons when near the end of the pagination
	if current_page > 5:
		if total_pages - current_page < 5:
			# Show last 10 pages when close to the last page
			start_page = max(1, total_pages - max_visible_buttons + 1)
			end_page = total_pages
		else:
			# Normal behavior: Keep current page centered
			start_page = max(1, current_page - 4)
			end_page = min(total_pages, current_page + 5)

	for page in range(start_page, end_page + 1):
		var page_button = _create_page_button(page)
		if page == current_page:
			page_button.button_pressed = true
			page_button.disabled = true

	# Next and Last Buttons
	_create_nav_button("Next", current_page + 1, current_page < total_pages)
	_create_nav_button("Last", total_pages, current_page < total_pages)


func _create_nav_button(label: String, target_page: int, enabled: bool) -> void:
	var button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(button_width, 0)
	button.disabled = not enabled
	button.connect("pressed", _on_nav_button_pressed.bind(target_page))
	add_child(button)


func _create_page_button(page: int) -> Button:
	var button = Button.new()
	button.text = str(page)
	button.custom_minimum_size = Vector2(button_width, 0)
	button.connect("pressed", _on_page_button_pressed.bind(page))
	add_child(button)
	return button


func _on_nav_button_pressed(target_page: int) -> void:
	current_page = clamp(target_page, 1, total_pages)
	emit_signal("page_changed", current_page)
	_draw_pagination()


func _on_page_button_pressed(page: int) -> void:
	current_page = page
	emit_signal("page_changed", current_page)
	_draw_pagination()


# Clears the HBoxContainer before redrawing the buttons
func clear() -> void:
	for child in get_children():
		child.queue_free()
