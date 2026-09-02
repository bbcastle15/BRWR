class_name GameEvent
extends RefCounted


var event_type: String = ""
var action_type: String = ""
var source_model_type: String = ""
var source_player_index: int = -1
var source_evocation: EvocationState = null

var target_model_type: String = ""
var target_player_index: int = -1
var target_evocation: EvocationState = null
var cancelled: bool = false
var redirected_evocation: EvocationState = null	
var suppressed_trigger_types: Array[String] = []
var source_room_id: String = ""
var target_room_id: String = ""

var amount: int = 0

var data: Dictionary = {}


func _init(
	type: String,
	event_data: Dictionary = {}
):
	event_type = type
	data = event_data
