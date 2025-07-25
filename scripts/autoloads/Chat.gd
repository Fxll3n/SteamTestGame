extends CanvasLayer

const CHAT_SCENE = preload("res://scenes/prefabs/chat_scene.tscn")

var chat_history: Array[Dictionary] = []
var chat: Control
var chat_line_edit: LineEdit
var chat_rtl: RichTextLabel

func _init() -> void:
	Network.recieved_packet.connect(_on_packet_received)

func _ready() -> void:
	chat = CHAT_SCENE.instantiate()
	add_child(chat)
	
	chat_line_edit = chat.get_node("PanelContainer/MarginContainer/VBoxContainer/LineEdit")
	chat_rtl = chat.get_node("PanelContainer/MarginContainer/VBoxContainer/RichTextLabel")
	

func send_message(message_data: Dictionary) -> void:
	chat_history.append(
		{
			"author": message_data["author"],
			"message": message_data["message"]
		}
	)
	update_chat()

func update_chat() -> void:
	chat_rtl.text = ""
	for message in chat_history:
		chat_rtl.text += "[color=cyan][b]%s[/b]:[/color] %s\n" % [message["author"], message["message"]]

func _on_packet_received(data: Dictionary) -> void:
	if data["tag"] != "message":
		return
	
	send_message(data)
