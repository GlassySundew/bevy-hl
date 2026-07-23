import bevy.Entity;
import bevy.System;

@:priority(30)
class SameFrameReplSystem extends System {
    @:upd function update(_ : ChainSpawn, entity : Entity):Void {
        world.add(entity, (0 : ChainRepl));
    }
}
