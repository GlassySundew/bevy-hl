import bevy.Entity;
import bevy.System;

class FilteredEventSystem extends System {
	public var received( default, null ) : Int = 0;
	public var value( default, null ) : Int = 0;
	public var lastEntity( default, null ) : Entity;
	public var lastPosition( default, null ) : Position;

	@:event
	@:exclude( Sleeping )
	function onEntityEvent(
		event : EntityEvent,
		position : Position,
		entity : Entity,
		dt : Float
	) : Void {
		received++;
		value += event.value;
		lastEntity = entity;
		lastPosition = position;
	}
}
