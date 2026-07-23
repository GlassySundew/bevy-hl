import bevy.System;

class DamageEventSystem extends System {
    public var received(default, null):Int = 0;
    public var totalDamage(default, null):Int = 0;
    public var lastTickLength(default, null):Float = 0;

    @:event
    function onDamage(event:DamageEvent, dt:Float):Void {
        received++;
        totalDamage += event.amount;
        lastTickLength = dt;
    }
}
