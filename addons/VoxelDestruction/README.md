	Welcome to the Voxel Destruction addon for Godot 4.3+. 
This addon provides a flexible and efficient voxel-based destruction system, 
allowing you to create dynamic, destructible objects from .vox imports.
--------------------------------------------------------------------------------
Report Issues Here: https://github.com/Terabase-Studios/Godot-Voxel-Destruction/issues
Github Repo: https://github.com/Terabase-Studios/Godot-Voxel-Destruction
Wiki: https://github.com/Terabase-Studios/Godot-Voxel-Destruction/wiki

***Disclamer: If you have run the demo you probably have seen four things:
	1: Everytime you shoot, the first tap may not damage the cubes or damaging 
	the cubes is inconsistant. This is because Godot is weird when it comes to 
	updating Area3D's when position is changed.
	
	2. Rigidbodies for debri may lag the game and disappear. There is a rigidbody
	debris cap that rmoves excess debris. Also, every Rigidbody debri is its
	own physics object which slows down the game for sure. I would recommend
	using the Jolt physics engine in project setting. However, you would 
	need to turn on Areas Detect Static Bodies in 
	physics/jolt_physics_3d/simulation/areas_detect_static_bodies**
	
	I Hope You All Enjoy. If you like this addon and want to see its development
	then checkout the github repo. Feel free to submit issues or comment on the
	ones I made. You should also find a roadmap there to under projects.

	Goodluck with your projects and thank you for choosing Terabase. <3
