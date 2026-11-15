class_name EditorContext
extends RefCounted

## The main-scene nodes that an editor plugin uses.
##
## [Main] fills one context after its nodes are ready. [PluginHost] gives it to
## each plugin before the plugin enters the tree, so a plugin reads the fields in
## its own `_ready` without a tree search.

## The main scene that owns the editor.
var main: Node
## The application menu bar.
var menu_bar: Control
## The tab container that holds the editor tab and the plugin tabs.
var tab_container: TabContainer
## The editor tab.
var editor_tab: Control
## The tool bar.
var tool_bar: Control
## The option bar.
var option_bar: Control
## The viewport control bar.
var control_bar: Control
## The viewport that shows the scene.
var viewport: Control
## The node under the viewport that holds the tool nodes.
var viewport_scene: Node3D
## The editor workspace that registers the tool buttons.
var workspace: Node
