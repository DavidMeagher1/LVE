extends "res://plugins/paint/FillTool.gd".FillJob

var checks := 0
var cancel_after := 1


func checkpoint(completed: int) -> bool:
	checks += 1
	if checks > cancel_after:
		cancel()
	return super.checkpoint(completed)
