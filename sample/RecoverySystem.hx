import bevy.System;

class RecoverySystem extends System {
	public var updates( default, null ) : Int = 0;

	@:update
	function updateAfterFailure( dt : Float ) : Void {
		updates++;
	}
}
