import bevy.System;

@:priority(10)
class FaultingSystem extends System {
	public var attempts( default, null ) : Int = 0;

	@:update
	function failOnce( dt : Float ) : Void {
		attempts++;
		if ( attempts == 1 ) throw "intentional sample system failure";
	}
}
