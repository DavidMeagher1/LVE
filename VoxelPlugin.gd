class_name VoxelPlugin extends Node

## Base class for an editor plugin.
##
## A plugin adds its controls to the main scene and its tool node to the
## viewport. It registers the controls through the helpers in this class.

func _safe_add(parent:Node, child:Node) -> void:
	if child.get_parent():
		child.reparent(parent)
		return
	parent.add_child(child)
	
func _safe_remove(parent:Node, child:Node) -> void:
	if not child.get_parent() == parent:
		return
	parent.remove_child(child)


## The button that activates this plugin. [method add_tool_bar_item] sets it, so
## the base routes its toggle and releases it. A plugin never touches button
## state.
var _tool_button: BaseButton


## Activates the tool. A plugin with a tool button overrides this.
func activate_tool() -> void:
	pass


## Deactivates the tool. The base releases the tool button, then runs
## [method _end_deactivation] once. A plugin overrides only that method.
func deactivate_tool() -> void:
	if is_instance_valid(_tool_button):
		# This engine call clears the button without a `toggled` signal, so the
		# release cannot re-enter this call. A ButtonGroup finds its pressed
		# button by reading the buttons, so the group sees the release.
		_tool_button.set_pressed_no_signal(false)
	_end_deactivation()


## Ends this plugin's tool. The base calls it once per deactivation.
func _end_deactivation() -> void:
	pass


## Routes one tool button to this plugin. The shared ButtonGroup keeps the pressed
## state, so this listener only maps the button to the tool.
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


## Returns the current main scene. A test scene puts Main below its test root,
## so the plugins find it through the group instead of a fixed tree path.
func _main() -> Node:
	# A deferred call can run after the plugin left the tree. `get_tree` is null
	# then, so every caller must handle a missing Main.
	return get_tree().get_first_node_in_group("main") if is_inside_tree() else null

## Adds a control to the menu bar before its separator.
func add_menu_bar_item(control:Control) -> void:
	var menu_bar := _main().get_node("%MenuBar")
	_safe_add(menu_bar, control)
	var separator_index := menu_bar.get_node("Sep1").get_index()
	if control.get_index() < separator_index:
		separator_index -= 1
	menu_bar.move_child(control, separator_index)

## Removes a control from the menu bar.
func remove_menu_bar_item(control:Control) -> void:
	_safe_remove(_main().get_node("%MenuBar"), control)

## Adds a control as a tab. A control that is not current is disabled.
func add_tab(control: Control) -> void:
	var tabs: TabContainer = _main().get_node("%TabContainer")
	_safe_add(tabs, control)
	control.process_mode = Node.PROCESS_MODE_INHERIT if tabs.get_current_tab_control() == control else Node.PROCESS_MODE_DISABLED

## Removes a tab. It shows the editor tab when the removed tab was current.
func remove_tab(control: Control) -> void:
	var main := _main()
	if main == null:
		return
	var tabs: TabContainer = main.get_node("%TabContainer")
	if tabs.get_current_tab_control() == control:
		show_editor_tab()
	_safe_remove(tabs, control)

## Shows one tab. It does nothing when the control is not a tab.
func show_tab(control: Control) -> void:
	var tabs: TabContainer = _main().get_node("%TabContainer")
	if control.get_parent() == tabs:
		tabs.current_tab = tabs.get_tab_idx_from_control(control)

## Shows the editor tab.
func show_editor_tab() -> void:
	show_tab(_main().get_node("%Editor"))

## Adds a control to the option bar.
func add_option_bar_item(control: Control) -> void:
	_safe_add(_main().get_node("%OptionBar"), control)

## Removes a control from the option bar.
func remove_option_bar_item(control: Control) -> void:
	_safe_remove(_main().get_node("%OptionBar"), control)

## Adds a control to the viewport control bar.
func add_control_bar_item(control:Control) -> void:
	_safe_add(_main().get_node("%Viewport").get_node("%ControlBar"), control)

## Removes a control from the viewport control bar.
func remove_control_bar_item(control:Control) -> void:
	_safe_remove(_main().get_node("%Viewport").get_node("%ControlBar"), control)

## Adds a control to the tool bar. An optional settings resource registers with
## the editor workspace, so its values follow the active document.
func add_tool_bar_item(control:Control, settings: Resource = null) -> void:
	var main := _main()
	if main == null:
		return
	_safe_add(main.get_node("%ToolBar"), control)
	if control is BaseButton:
		_set_tool_button(control)
	var workspace := main.get_node_or_null("%EditorWorkspace")
	if workspace != null and control is BaseButton:
		workspace.call("register_tool", "%s/%s" % [name, control.name], control, settings)

## Removes a control from the tool bar. A removed tool button no longer routes to
## this plugin or writes the active tool.
func remove_tool_bar_item(control:Control) -> void:
	var main := _main()
	if main == null:
		return
	_safe_remove(main.get_node("%ToolBar"), control)
	var workspace := main.get_node_or_null("%EditorWorkspace")
	if workspace != null and control is BaseButton:
		workspace.call("unregister_tool", "%s/%s" % [name, control.name])
	if not is_instance_valid(_tool_button) or control != _tool_button:
		return
	if _tool_button.toggled.is_connected(_on_tool_button_toggled):
		_tool_button.toggled.disconnect(_on_tool_button_toggled)
	_tool_button = null

## Adds a tool node to the viewport scene.
func add_editor_node(node:Node3D) -> void:
	_safe_add(_main().get_node("%Viewport").get_node("%ViewportScene"), node)
	
## Removes a tool node from the viewport scene.
func remove_editor_node(node:Node3D) -> void:
	_safe_remove(_main().get_node("%Viewport").get_node("%ViewportScene"), node)
	
