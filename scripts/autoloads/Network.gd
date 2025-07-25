extends Node

## Handles Steam P2P networking.
## [br]
## Creates and joins Steam lobbies, sends and receives packets,
## and keeps track of lobby members.

## Emitted when a packet is received.
## [br]
## [param packet_data] A [Dictionary] that always includes a [code]"tag"[/code] key  
## to identify what kind of packet it is.
signal recieved_packet(packet_data: Dictionary)

## Max number of packets to read per frame.
## [br]
## Helps avoid overloading the system when lots of data comes in.
const PACKET_READ_LIMIT: int = 32

## Max players allowed in a lobby.
const LOBBY_MEMBER_LIMIT: int = 2

## True if this peer is the host of the lobby.
var is_host: bool = false

## The ID of the lobby we’ve created or joined.
## [br]
## Will be [code]0[/code] if no lobby is active.
var lobby_id: int = 0

## List of members in the current lobby.
## [br]
## Each entry is a dictionary with [code]"steam_id"[/code] and [code]"username"[/code].
var lobby_members: Array = []

func _init() -> void:
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

func _process(delta: float) -> void:
	if not Steam.isSteamRunning():
		print("[Network] Steam not running.")
		return
	
	read_all_p2p_packets()

## Creates a public Steam lobby.
## [br]
## Does nothing if you're already in a lobby.
func create_lobby() -> void:
	if lobby_id != 0:
		push_warning("[Network] Already in a lobby: %s" % lobby_id)
		return
	is_host = true
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, LOBBY_MEMBER_LIMIT)

## Joins an existing Steam lobby.
## [param this_lobby_id] The ID of the lobby to join.
func join_lobby(this_lobby_id: int) -> void:
	Steam.joinLobby(this_lobby_id)

## Updates and returns the list of current lobby members.
## [br]
## Emits [code]member_list_updated[/code] (not shown here) when updated.
func get_lobby_members() -> Array:
	lobby_members.clear()
	var num_members = Steam.getNumLobbyMembers(lobby_id)
	
	for i in range(num_members):
		var steam_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		var username = Steam.getFriendPersonaName(steam_id)
		lobby_members.append({
			"steam_id": steam_id,
			"username": username
		})
	emit_signal("member_list_updated", lobby_members)
	return lobby_members

## Sends a packet to one player or all players.
## [br]
## [param this_target] Set to 0 to broadcast to everyone.
## [param packet_data] Dictionary with the data to send.
## [param send_type] Optional send type (default is 0).
func send_p2p_packet(this_target: int, packet_data: Dictionary, send_type: int = 0) -> void:
	var channel = 0
	var this_data: PackedByteArray
	
	packet_data["steam_id"] = Steam.getSteamID()
	packet_data["username"] = Steam.getPersonaName()
	this_data.append_array(var_to_bytes(packet_data))
	
	if this_target == 0:
		for member in lobby_members:
			if member["steam_id"] != Steam.getSteamID():
				Steam.sendP2PPacket(member["steam_id"], this_data, send_type, channel)
	else:
		Steam.sendP2PPacket(this_target, this_data, send_type, channel)

## Reads a single incoming packet.
## [br]
## If it contains a [code]"tag"[/code], emits [code]recieved_packet[/code].
func read_p2p_packet() -> void:
	var packet_size = Steam.getAvailableP2PPacketSize()
	
	if packet_size > 0:
		print("[Network] Received a packet.")
		var packet = Steam.readP2PPacket(packet_size)
		var raw_data = packet["data"]
		var data = bytes_to_var(raw_data)
		
		if data.has("tag"):
			print("[Network] Packet has tag.")
			recieved_packet.emit(data)
			
			if data["tag"] == "handshake":
				print("[Network] Got handshake from %s (%s)" % [data["steam_id"], data["username"]])
				print("[Network] %s joined the lobby." % data["username"])
				get_lobby_members()

## Reads all available packets this frame, up to the limit.
func read_all_p2p_packets(read_count: int = 0) -> void:
	if read_count > PACKET_READ_LIMIT:
		return
	
	if Steam.getAvailableP2PPacketSize() > 0:
		read_p2p_packet()
		read_all_p2p_packets(read_count + 1)

## Sends a handshake packet to all lobby members.
func make_p2p_handshake() -> void:
	send_p2p_packet(0, {
		"tag": "handshake"
	})
	print("[Network] Sent handshake.")

## Called when a lobby is created.
func _on_lobby_created(connect: int, this_lobby_id: int) -> void:
	if connect != 1:
		push_warning("[Network] Lobby creation failed: %s" % connect)
		return
	
	lobby_id = this_lobby_id
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "name", "%s's Lobby" % Steam.getPersonaName())
	Steam.allowP2PPacketRelay(true)
	print("[Network] Created lobby: %s" % lobby_id)

## Called when successfully joined a lobby.
func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_warning("Failed to join lobby %s: %s" % [this_lobby_id, response])
		return
	
	lobby_id = this_lobby_id
	print("[Network] Joined lobby: %s" % lobby_id)
	get_lobby_members()
	make_p2p_handshake()

## Accepts P2P session requests from other players.
func _on_p2p_session_request(remote_id: int) -> void:
	var username = Steam.getFriendPersonaName(remote_id)
	Steam.acceptP2PSessionWithUser(remote_id)
