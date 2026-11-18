class_name VoxelPlugin extends Node


func _safe_add(parent:Node, child:Node) -> void:
	if parent == null or child == null:
		return
	if child.get_parent():
		child.reparent(parent)
		return
	parent.add_child(child)

func _safe_remove(parent:Node, child:Node) -> void:
	if parent == null or child == null:
		return
	if not child.get_parent() == parent:
		return
	parent.remove_child(child)


var context: EditorContext


var _tool_button: BaseButton


func activate_tool() -> void:
	pass


func deactivate_tool() -> void:
	if is_instance_valid(_tool_button):
		_tool_button.set_pressed_no_signal(false)
	_end_deactivation()


func _end_deactivation() -> void:
	pass


func _set_tool_button(button: BaseButton) -> void:
	if is_instance_valid(_tool_button) and _tool_button != button and _tool_button.toggled.is_connected(_on_tool_button_toggled):
		_tool_button.toggled.disconnect(_on_tool_button_toggled)
	_tool_button = button
	if not _tool_button.toggled.is_connected(_on_tool_button_toggled):
		_tool_button.toggled.connect(_on_tool_button_toggled)


func _on_tool_button_toggled(on: bool) -> void:
	if on:
		activate_tool()
	else:
		deactivate_tool()


var _tool_button_ids := {}


func add_menu_bar_item(control:Control) -> void:
	if context == null or context.menu_bar == null:
		return
	var menu_bar := context.menu_bar
	_safe_add(menu_bar, control)
	var separator_index := menu_bar.get_node("Sep1").get_index()
	if control.get_index() < separator_index:
		separator_index -= 1
	menu_bar.move_child(control, separator_index)

func remove_menu_bar_item(control:Control) -> void:
	if context == null or context.menu_bar == null:
		return
	_safe_remove(context.menu_bar, control)

func add_tab(control: Control) -> void:
	if context == null or context.tab_container == null:
		return
	var tabs := context.tab_container
	_safe_add(tabs, control)
	control.process_mode = Node.PROCESS_MODE_INHERIT if tabs.get_current_tab_control() == control else Node.PROCESS_MODE_DISABLED

func remove_tab(control: Control) -> void:
	if context == null or context.tab_container == null:
		return
	var tabs := context.tab_container
	if tabs.get_current_tab_control() == control:
		show_editor_tab()
	_safe_remove(tabs, control)

func show_tab(control: Control) -> void:
	if context == null or context.tab_container == null:
		return
	var tabs := context.tab_container
	if control.get_parent() == tabs:
		tabs.current_tab = tabs.get_tab_idx_from_control(control)

func show_editor_tab() -> void:
	if context == null or context.editor_tab == null:
		return
	show_tab(context.editor_tab)

func add_option_bar_item(control: Control) -> void:
	if context == null or context.option_bar == null:
		return
	_safe_add(context.option_bar, control)

func remove_option_bar_item(control: Control) -> void:
	if context == null or context.option_bar == null:
		return
	_safe_remove(context.option_bar, control)

func add_control_bar_item(control:Control) -> void:
	if context == null or context.control_bar == null:
		return
	_safe_add(context.control_bar, control)

func remove_control_bar_item(control:Control) -> void:
	if context == null or context.control_bar == null:
		return
	_safe_remove(context.control_bar, control)

func add_tool_bar_item(control:Control, settings: Resource = null, tool_id := "") -> void:
	if control == null:
		return
	var id := tool_id if not tool_id.is_empty() else String(control.name)
	control.set_meta("tool_id", id)
	if context == null or context.tool_bar == null:
		return
	_safe_add(context.tool_bar, control)
	if control is BaseButton:
		_set_tool_button(control)
		_tool_button_ids[control] = id
	if context.workspace != null and control is BaseButton:
		context.workspace.call("register_tool", "%s/%s" % [name, id], control, settings)

func remove_tool_bar_item(control:Control) -> void:
	if control == null:
		return
	var id := String(_tool_button_ids.get(control, ""))
	if id.is_empty() and control is BaseButton:
		id = str(control.get_meta("tool_id", control.name))
	_tool_button_ids.erase(control)
	if context != null and context.tool_bar != null:
		_safe_remove(context.tool_bar, control)
	if context != null and context.workspace != null and control is BaseButton and not id.is_empty():
		context.workspace.call("unregister_tool", "%s/%s" % [name, id])
	if not is_instance_valid(_tool_button) or control != _tool_button:
		return
	if _tool_button.toggled.is_connected(_on_tool_button_toggled):
		_tool_button.toggled.disconnect(_on_tool_button_toggled)
	_tool_button = null

func add_editor_node(node:Node3D) -> void:
	if context == null or context.viewport_scene == null:
		return
	_safe_add(context.viewport_scene, node)

func remove_editor_node(node:Node3D) -> void:
	if context == null or context.viewport_scene == null:
		return
	_safe_remove(context.viewport_scene, node)
