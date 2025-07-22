# Cortex API

Cortex is a framework for handling Roblox NPC characters. It provides basic functionality common to most all NPCs. Using the framework allows you to rapidly add functional NPCs to your game with common movement supported by pathfinding. Common target detection capabilities that are supported by events. Movement and detection capabilities can be combined with one another to accomplish many common tasks. Further combine with your own unique NPC methods to create highly sophisticated NPCs for any game.

### FUNCTIONS
New(NPC: Model, ap: AgentParams, animScript: any) - Creates a new Cortex instance for the provided NPC Model
GetInstance(NPC: model, wait: boolean) - Returns the Cortex instance associated with the NPC model provided
GetWaypointObj() - Returns a copy of the default waypoint object for path tracing

### METHODS
Disable() - Disables the NPC Cortex instance
Enable() - Enables the NPC Cortex instance
SetSpeed(speed: number) - Sets the default walk/move speed of the NPC
GetMoveMode() - Returns the Name and value of the current move mode
Spawn(point: Point, parent: Instance?, lifetime: number?) - Spawns the NPC at the specified Vector3 or CFrame point provided. If parent is not supplied the NPC is parented to the NPC directory set in Utility module. If lifetime is supplied the NPC will despawn when it expires. (Un-Safe spawn type)
SafeSpawn(point: Point, lookAt: Vector3, lifetime: number, parent: Instance) - Utilizes Teleport() method while spawning to ensure the NPC spawns safely into the game map.
Teleport(point: Point, lookAt: Vector3, unsafe: boolean) - Relocates NPC within the game in a safe manner unless unsafe is set true. If lookAt is provided, the NPC will be faced in the lookAt direction. (Safe manner means that checks will be performed for blockages and landing surface.)

### TRAVEL MODE
TravelTo(dest: Point, finalDest: boolean) - Attempts to have the NPC travel to the destination point provided and sets the MoveMode to Traveling
TravelPath(waypoints: {PathWaypoint}) - Attempts to have the NPC travel the path of waypoints provided and sets the MoveMode to Traveling
PauseTravel() - Pauses traveling to the currently set destination. Can be resumed.
ResumeTravel() - Resumes traveling to the currently set destination.
StopTravel() - Cancels traveling to the currently set dest. Cannot be resumed.

### PATROL MODE
Patrol(route: {}) - NPC Travels back and forth between end points along specified route/path.
PausePatrol() - Pauses traveling the patrol route. Can be resumed.
ResumePatrol() - Resumes traveling the current patrol route.
StopPatrol() - Cancels traveling the current patrol route. Cannot be resumed.
SetPatrolPoints(patrolPoints: {Point}) - Sets a table of patrol points that can be used by the NPC for creating patrol routes.
SetPatrolRoute(route: {}) - Sets the patrol route to use when Patrolling. If no route provided then a random route is created using the set patrol points (if any).

### TRACKING MODE - Requires Character Detection
Track(target: Model | BasePart) - NPC attempts to find the target specified anywhere within the game map regardless if the target is moving or not.
StopTrack() - Cancels tracking the currently set tracking target.

### CHASE MODE - Requires Character Detection
Chase(target: Model | BasePart) - NPC chases after the target specified. The target can either Escape or be Caught by the NPC. If target is caught or escapes, chasing ends and the appropriate event is fired.
StopChase() - Cancels chasing the currently set target.

### FOLLOW MODE - Requires Character Detection
Follow(target: Model | BasePart) - NPC follows the specified target. When following the NPC stays within the set range of the target.
StopFollow() - Cancels following the currently set target.


## CHARACTER DETECTION

New(NPC: Model, range: NumberRange, focusRange: NumberRange, gracePeriod: NumberRange) - Creates a new character detection instance for the NPC specified.

### Detection Methods
ShowRange(opts: "All | Detect | Focus") - Displays the specified detection range type used by the NPC.
HideRange(opts: "All | Detect | Focus") - Hides the display for the specified detection range type used by the NPC.
SetDetectionRange(range: NumberRange) - Sets the distance range to use for normal detection.
SetFocusRange(range: NumberRange) - Sets the distance range to use for focused detection.
SetFocusGrace(range: NumberRange) - Sets the grace periods (in secs) for focused detection events. (Min = CloseFocus Grace, Max = FocusLost Grace)

### Targeting Methods
AddCharTarget(char: Model) - Adds the specified character model as a detectable target for the NPC. (Use for character models)
RemoveCharTarget(char: Model) - Removes the specified character model as a detectable target for the NPC. (Use for character models)
AddTarget(target: Instance) - Adds the specified target as a detectable target for the NPC. (Use for non-character targets)
RemoveTarget(target: Instance) - Removes the specified target as a detectable target for the NPC. (Use for non-character targets)

### Targeting Events
TargetDetected - Fires when the target first enters min detection range.
TargetLost - Fires when the target leaves max detection range. Or LineOfSight is lost.
TargetFocusLost - Fires when target is leaves max focus range and max grace time has expired. (Escaped)
TargetFocusGain - Fires when the target re-enters max focus range and NPC has LineOfSight and max grace time has NOT expired.
TargetFocusOut - Fires when the target leaves max focus range but grace time has NOT yet expired.
TargetCloseFocus - Fires when the target is within min focus range and the min grace period has expired. (Caught)
TargetInFocus - Continuously fires while the target is between min/max focus range and NPC has LineOfSight.
