import bevy.System;

@:priority(30)
class SameFrameSpawnSystem extends System {
    public var spawned = false;

    @:upd function update():Void {
        if (spawned) return;
        final entity = world.spawn();
        world.add(entity, (0 : ChainSpawn));
        world.add(entity, (0 : ChainPlayer));
        spawned = true;
    }
}
