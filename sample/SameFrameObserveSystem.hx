import bevy.System;

@:priority(30)
class SameFrameObserveSystem extends System {
    public var matches = 0;

    @:upd function update(
        _ : ChainSpawn,
        _ : ChainRepl,
        _ : ChainPlayer,
        entity : LegacyEntity
    ):Void {
        matches++;
        if (matches == 1)
            world.add(entity, (true : ChainReady));
    }
}
