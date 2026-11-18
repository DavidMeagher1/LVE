extends "res://tests/test.gd"


func _ready() -> void:
	test("the first duplicate test", _first, "same")
	test("the second duplicate test", _second, "same")


func _first() -> void:
	expect(true, "the first duplicate test never runs")


func _second() -> void:
	expect(true, "the second duplicate test never runs")
