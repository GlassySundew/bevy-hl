import bevy.System;

class PulseSystem extends System {
    public var ticks(default, null):Int = 0;
    public var elapsed(default, null):Float = 0;

    @:update
    function pulse(dt:Float):Void {
        ticks++;
        elapsed += dt;
    }
}
