import bevy.System;
import bevy.SystemStopReason;

class FailingActivationSystem extends System {
	public final log : Array<String> = [];

	override function onActivate() : Void {

		lifetime.defer( () -> log.push( "cleanup" ) );
		throw "activation failure";
	}

	override function onStop( reason : SystemStopReason ) : Void {

		log.push( switch reason {
			case ActivationFailed( _ ): "activation-failed";
			default: "unexpected-stop";
		} );
	}
}
