extends "res://tests/test.gd"


func _ready() -> void:
	test("a test with no check fails", _no_checks, "no_checks")


func _no_checks() -> void:
	print("this test records no check")
