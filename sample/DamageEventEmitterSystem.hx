import bevy.System;

@:priority(10)
class DamageEventEmitterSystem extends System {
    var sent:Bool = false;

    @:update
    function emitOnce(dt:Float):Void {
        if (!sent) {
            sent = true;
            emitEvent(new DamageEvent(3));
        }
    }
}
