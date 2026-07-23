package bevy;

/** Why an active system's activation scope ended. */
enum SystemStopReason {
	Removed;
	ParentStopped;
	WorldClosing;
	Reparented;
	ActivationFailed( error : haxe.Exception );
}
