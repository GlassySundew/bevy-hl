import bevy.System;

class ResourceSystem extends System {
	@:resource var config : IGameConfig;
	public var observedSpeed( default, null ) : Float = 0;

	@:update
	function readResource( dt : Float ) : Void {
		observedSpeed = config.speed;
	}
}
