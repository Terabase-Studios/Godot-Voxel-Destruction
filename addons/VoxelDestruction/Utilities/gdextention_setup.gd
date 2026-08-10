@tool
extends Node
class_name GDextensionSetup


const REPO_RELEASE_DOWNLOAD_BASE := "https://github.com/Terabase-Studios/Godot-Voxel-Destruction/releases/download/"
const RELEASE_PATH := "res://addons/VoxelDestruction/Rust/voxel_native/target/release/"
const DEBUG_PATH := "res://addons/VoxelDestruction/Rust/voxel_native/target/debug/"
const BINARIES := ["libvoxel_native.so", "voxel_native.dll", "libvoxel_native.dylib"]

var _running := false

func setup():
	if _running:
		return
	_running = true
	var popup = await VoxelDestructionGodot.create_process("Setting up GDextension", "Preparing")

	# Create target folder
	DirAccess.make_dir_recursive_absolute("res://addons/VoxelDestruction/Rust/voxel_native/target/debug")
	DirAccess.make_dir_absolute("res://addons/VoxelDestruction/Rust/voxel_native/target/release")

	# Get missing binaries - might be a good idea to just redownload in case of corruption
	var release_binaries_to_download := {}
	var debug_binaries_to_download := {}
	for binary: String in BINARIES:
		if not binary in DirAccess.get_files_at(RELEASE_PATH) or true: # Always retrieve
			release_binaries_to_download[binary] = RELEASE_PATH + binary
		if not binary in DirAccess.get_files_at(DEBUG_PATH) or true: # Always retrieve
			debug_binaries_to_download[binary] = DEBUG_PATH + binary
	var total_files_to_download := release_binaries_to_download.size() + debug_binaries_to_download.size() + 1
	var files_downloaded := 0

	# Download files from github release pages
	popup.text = "Downloading GDextension binaries"
	var tag := "v" + get_plugin_version()
	for binary in release_binaries_to_download.keys():
		popup.sub_text = "Downloading release binary: %s" % binary
		await popup.redraw()
		var download_from = REPO_RELEASE_DOWNLOAD_BASE + tag + "/" + binary
		download_from = "https://raw.githubusercontent.com/godotengine/godot/master/README.md"
		var save_to = release_binaries_to_download[binary]
		await download(download_from, save_to, binary)
		popup.text = "Downloading GDextension binaries"
		files_downloaded += 1
		popup.progress = float(files_downloaded) / float(total_files_to_download)
		await popup.redraw()
	for binary in debug_binaries_to_download.keys():
		popup.sub_text = "Downloading debug binary: %s" % binary
		await popup.redraw()
		var download_from = REPO_RELEASE_DOWNLOAD_BASE + tag + "/" + binary
		var save_to = debug_binaries_to_download[binary]
		await download(download_from, save_to, binary)
		popup.text = "Downloading GDextension binaries"
		files_downloaded += 1
		popup.progress = float(files_downloaded) / float(total_files_to_download)
		await popup.redraw()

	popup.text = "Finalizing GDextension setup"
	popup.sub_text = "please wait..."
	await popup.redraw()
	var download_from = "https://raw.githubusercontent.com/Terabase-Studios/Godot-Voxel-Destruction/refs/heads/main/addons/VoxelDestruction/Rust/voxel_native.txt"
	var save_to = "res://addons/VoxelDestruction/Rust/voxel_native.gdextension"
	await download(download_from, save_to, "voxel_native.gdextension")

	popup.text = "Set <rust_gdextention> to true in project settings"
	popup.sub_text = "GDextension setup complete"
	popup.progress = 1.0
	get_tree().create_timer(3).connect("timeout", popup.queue_free)


func download(download_from: String, save_to: String, binary: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.use_threads = true
	http.download_file = save_to
	http.max_redirects = 8

	var err := http.request(download_from)
	if err != OK:
		error("Failed to start download for %s, ERROR_CODE: %s" % [binary, err])
		http.queue_free()
		return

	var result: Array = await http.request_completed
	var response_code: int = result[1]

	if response_code != 200:
		error("Failed to download %s. HTTP %d" % [binary, response_code])
		if FileAccess.file_exists(save_to):
			DirAccess.remove_absolute(save_to)
		http.queue_free()
		return

	http.queue_free()


func error(msg: String):
	pass


func get_plugin_version() -> String:
	var config_path = "res://addons/VoxelDestruction/plugin.cfg"
	var config = ConfigFile.new()
	
	# Load and parse the plugin.cfg file
	if config.load(config_path) == OK:
		# Read the version key from the [plugin] section
		var version = config.get_value("plugin", "version", "unknown")
		return version
		
	return "plugin.cfg not found"
