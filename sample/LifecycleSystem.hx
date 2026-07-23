import bevy.System;
import bevy.SystemStopReason;

class LifecycleSystem extends System {
	public final log : Array<String> = [];

	override function onActivate() : Void {

		log.push( "activate" );
		lifetime.defer( () -> log.push( "cleanup-first" ) );
		lifetime.defer( () -> log.push( "cleanup-second" ) );
	}

	override function onStop( reason : SystemStopReason ) : Void {

		log.push( 'stop:$reason' );
	}
}
