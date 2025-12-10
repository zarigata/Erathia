class_name Interactable
extends Node3D

signal on_focus
signal on_unfocus
signal on_interact

@export var prompt_text: String = "Interact"

func focus():
	on_focus.emit()

func unfocus():
	on_unfocus.emit()

func interact():
	on_interact.emit()
