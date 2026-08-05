import bevy.Entity;
import bevy.System;

@:priority(10)
class MovementSystem extends System {
    public var updates(default, null):Int = 0;

	public function replacePosition( entity : Entity, position : Position ) : Entity {

		return replaceComponent( entity, position );
	}

	public function addPositionIfMissing( entity : Entity, position : Position ) : Entity {

		return addComponentIfMissing( entity, position );
	}

    @:upd
    @:exclude(Sleeping)
    function move(position:Position, velocity:Velocity, entity:Entity, dt:Float):Void {
        position.x += velocity.x * dt;
        position.y += velocity.y * dt;
        updates++;
        trace('$entity moved to ${position.x}, ${position.y}');
    }
}
