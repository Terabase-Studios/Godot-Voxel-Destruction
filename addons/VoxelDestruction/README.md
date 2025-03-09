	Welcome to the Voxel Destruction addon for Godot 4.3+. 
This addon provides a flexible and efficient voxel-based destruction system, 
allowing you to create dynamic, destructible objects from .vox imports.
--------------------------------------------------------------------------------
Report Issues Here: https://github.com/Terabase-Studios/Godot-Voxel-Destruction/issues
Github Repo: https://github.com/Terabase-Studios/Godot-Voxel-Destruction
Wiki: https://github.com/Terabase-Studios/Godot-Voxel-Destruction/wiki

***Disclamer: If you have run the demo you probably have seen five things:
	1: Everytime you shoot the first tap freezes your character. This is because
	godot is weird when it comes to updating area3D's and it is the only way I was
	able to get it to work, I have since changed the way the VoxelDamager works
	but I have yet to change it. Use the profiler to check for lag spikes
	
	2: The memory is like half a gigabyte, I am aware of this and this is a result
	of every voxel having a voxel body. I am redesigning the collision system soon
	so don't you worry
	
	3: It gets pretty laggy when attacking voxels in rapid succession. Yep this is
	also a collsion problem. The profiler shows the scripts not taking much frame
	time. Processing however...
	
	4: So yes, the processing time is not good. I am not sure why this happens 
	but I believe it is a CPU bottleneck with rendering.
	
	5: λ_φ_coloration, this is just a fun experiment with maybe a voxel object 
	shader? I don't know if is is better than just adding a shader to the 
	multimeshes mesh material. But it is a fun experiment wiht overiding the
	get_vox_color() function based on vox position**
	
	I Hope You All Enjoy. If you like this addon and want to see its development
	then checkout the github repo. Feel free to submit issues or comment on the
	ones I made. You should also find a roadmap there to under projects.
	Goodluck with your projects and thank you for choosing Terabase. <3
