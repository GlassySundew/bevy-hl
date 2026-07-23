# Bevy ECS bridge for HashLink

This library embeds `bevy_ecs` 0.19 in a HashLink `.hdll`. It is intentionally
single-threaded for now and has an isolated Haxe sample

## Layout

- `rust/src/lib.rs` owns Bevy worlds, dynamic component registration, entities,
  and query snapshots.
- `bevy_hl.c` is the HashLink ABI shim. It roots Haxe component objects while
  Bevy owns them and releases the roots when Bevy drops or replaces them.
- `haxe/bevy` is the haxelib API and macro layer.
- `sample` exercises the current bridge without depending on the game.

The call path is:

```text
Haxe macro-generated code -> HashLink native primitive -> C ABI shim -> Bevy ECS
```

Haxe macros run in the compiler process; they do not call Bevy directly. They
resolve component types and storage metadata and assign each discovered type a
dense compile-time bridge ID. Generated component access uses integer literals;
there are no runtime type-name hashes or registration calls in the hot path.
When a world starts, it registers every discovered descriptor with Bevy once.
Because Bevy owns its internal `ComponentId` allocation, Rust retains a compact
per-world vector from bridge ID to Bevy ID. Dense IDs are recovered from
module-bound resources when `--connect` reuses a cached module, so incremental
compilation does not depend on macro execution order.

## Current API

```haxe
final world = new bevy.World();
final entity = world.spawn();

world.add(entity, new Position(1, 2));
world.add(entity, new Velocity(0.5, -1));

world.each([Position, Velocity], (entity, position, velocity) -> {
    position.x += velocity.x;
}, [Sleeping]);

final position = world.get(entity, Position);
world.has(entity, Velocity);
world.remove(entity, Velocity);
entity.despawn(world);
world.close();
```

Components use Bevy table storage by default. Mark a component class with
`@:bevySparseSet` to use sparse-set storage.

Primitive values and primitive-backed typedefs/abstracts can also be components,
for example `typedef Dirty = Bool` or `typedef Flags = Int`. Use an explicit
type annotation when inserting one so the macro records the alias rather than
the underlying primitive: `world.add(entity, (flags : UnitReplIngestFlags))`.

Debuggers and tooling can inspect the dynamic world without relying on internal
Bevy storage layouts. `world.entities()` returns a fresh live-entity snapshot,
and `world.componentsOf(entity)` returns `DynamicComponentStorage` views for
the components currently attached to that entity. These views expose canonical
and short type names and support the same get/add/remove operations as queries.

Queries currently materialize a snapshot of matching entity handles. Required
component values are passed to the callback in the same order as the type list;
the optional third list excludes components. Component objects remain ordinary
Haxe objects, so mutations made by Haxe are visible on later reads.

Reusable runtime query specifications are available for services and generic
systems such as `RelationBuild`:

```haxe
final query:bevy.QueryBase = world.getQuery(
    [ParentLink, ChildrenSlice],
    [Disabled]
);

final snapshot = query.entities;
for (entity in snapshot) {
    final parent:ParentLink = query.componentStorages[0].get(entity);
    final children:ChildrenSlice = query.componentStorages[1].get(entity);
}

query.iterUntyped((entity, components) -> {
    final parent:ParentLink = components[0];
});
```

The macro records component names, sparse/table metadata, and the IDs returned
for that world. `componentStorages` preserves required-list order and supports
`get`, `exists`, `add`, and `remove`; `excludeComponentStorage` describes the
negative filters.

The query object owns a persistent native Bevy `QueryState`. Every `entities`,
`length`, or iteration request refreshes that state into a reusable entity
buffer, so structural changes remain visible without rebuilding the query or
allocating a native cursor. Capture `final snapshot = query.entities` when
consistency across multiple passes matters. Snapshots are safe to iterate while
component operations structurally change the world.

## Build and run

Requirements for the checked-in Windows setup:

- HashLink source/build at `C:\Users\glassysundew\hashlink`
- Haxe on `PATH`
- CMake and Visual Studio 2019 C++ tools
- Rust 1.95.0 (selected by `rust-toolchain.toml`)

Place this project into your hashlink/libs/

Run:
```bat
build.bat
sample\run.bat
```

The sample runner builds `bevy.hdll`, compiles `sample.hxml`, copies the native
library beside the bytecode for execution, and removes that copy afterwards.
It uses this checkout's Debug HashLink executable; the bridge itself is built
in Release mode.

For library usage in haxe project:

```bat
haxelib dev bevy-hl {your\path\to\hashlink}\libs\bevy
```

(Don't forget to add bevy.hdll to your PATH(windows) or LD_LIBRARY_PATH(linux))

## Current constraints

- All world access and component destruction must happen on the owning
  HashLink thread.
- Haxe objects are opaque dynamically registered Bevy components. Native Rust
  systems cannot yet borrow their fields as typed Rust structs.
- Queries are immediate snapshots rather than cached Bevy `QueryState` values.
- Native Bevy schedules/messages, observers, relationships, and
  change detection are not exposed yet. The Haxe-facing system scheduler and
  typed event router are single-threaded and described below.

The next useful layers are native Bevy observers and change tracking. They can
reuse the same macro technique: compile-time Haxe types become stable runtime
registrations.

## Resources

Resources are Haxe objects stored once per type and per `World`. The explicit
declared type is the key, so interfaces can be used independently of their
concrete implementation:

```haxe
world.insertResource(IOverworldContext, new LocationOverworldContext(location));
final context = world.resource(IOverworldContext);       // required
final optional = world.tryResource(IOverworldContext);   // nullable
world.hasResource(IOverworldContext);
world.removeResource(IOverworldContext);
```

`setService` and `getService` are compatibility aliases for existing Echoes
code. Resource references are released by `world.close()`; their own disposal
remains the application's responsibility.

Systems can request resources on instance fields. They are fetched whenever
the system activates, before `onActivate()`, and an absent required resource
prevents activation with a descriptive error:

```haxe
class PathSystem extends bevy.System {
    @:resource var context:IOverworldContext;
    @:resource var paths:Pathfinder;
}
```

`system.resourceTypes` exposes the macro-collected canonical type names for
future scheduling and access validation.

## Systems and clocks

Extend `bevy.System` and mark entity listeners with `@:update` (or any
unambiguous Echoes-style prefix such as `@:u` or `@:upd`). The build macro reads
the method signature and creates one persistent Bevy query per listener during
system activation. Steady-state updates reuse the query and its component IDs:

```haxe
@:priority(10)
class MovementSystem extends bevy.System {
    @:update
    @:exclude(Sleeping)
    function move(position:Position, velocity:Velocity, entity:bevy.Entity, dt:Float) {
        position.x += velocity.x * dt;
    }
}

final movement = new MovementSystem(world);
movement.activate();              // attaches to world.activeSystems
world.update(frameDeltaSeconds);  // runs active systems
movement.deactivate();
```

Listener parameters are interpreted as follows:

- `bevy.Entity` receives the matching entity.
- `Float` receives the current system-list tick length.
- Required component arguments form the query.
- Optional component arguments are fetched without becoming query requirements.
- `@:exclude(ComponentA, ComponentB)` adds negative query filters.
- Class-level `@:priority(expression)` controls ordering within a list; higher
  priorities run first and equal priorities retain insertion order.

Systems may be grouped into nested `SystemList` values, each list owns a clock.:

```haxe
final anchorUpdates = new bevy.SystemList(world, "LocationAnchorUpdates");
anchorUpdates.clock.setFixedTickLength(10); // once per ten seconds
anchorUpdates.add(new LocationAnchorLifecycleUpdate(world));
world.activeSystems.add(anchorUpdates);
```

For rate-based configuration, `SystemList.atRate(world, 3, "Regen")` creates a
three-ticks-per-second list, and `clock.setRate(3)` changes an existing clock.
Clocks retain fractional leftover time, can tick multiple times to catch up,
and expose `paused`, `timeScale`, `maxTime`, and `maxTickLength` controls.

## Typed events

Events are declared where they are consumed: on system methods. `@:event`,
`@:onEvent`, `@:message`, and `@:bevy_event` are accepted spellings.

```haxe
class DamageEvent {
    public final amount:Int;

    public function new(amount) {
        this.amount = amount;
    }
}

class DamageSystem extends bevy.System {
    @:event
    function onDamage(event:DamageEvent, dt:Float):Void {
        trace('damage: ${event.amount}');
    }
}
```

Each matched entity and its required component values are transferred through
one bulk ABI call into a reusable row buffer. Optional components are fetched
separately because they do not participate in the required query layout.

Publish from ordinary code through the world, or from another system with the
`emitEvent` helper:

```haxe
world.send(new DamageEvent(entity, 5));       // current tick (offset 0)
world.send(new DamageEvent(entity, 5), 1);    // next tick
emitEvent(new DamageEvent(entity, 5), 2);     // two ticks later, inside a System
```

The event macro assigns every discovered event type a dense integer ID. The
type-name-to-ID map exists only in the macro process; at runtime each world
eagerly creates an `EventChannel<T>` for every discovered ID and emission uses
direct array indexing. Channel payload arrays and listener callbacks remain
typed rather than `Dynamic`.

Delivery has deterministic tick semantics:

- Offset `0` is readable during the current world tick. An earlier system can
  therefore emit to a later system in the same ordered `SystemList` update.
- Offset `1` is readable on the next `world.update()`, offset `2` two updates
  later, and so on. Negative offsets are rejected.
- An event exists for exactly its selected delivery tick and is discarded when
  that world update ends. A paused or throttled listener which does not run in
  that tick intentionally misses it.
- Every active handler keeps an independent cursor over the shared typed array,
  so multiple systems see the same events and repeated clock steps do not
  consume the same event twice.
- A same-tick event cannot travel backward through system order: if its consumer
  already ran, use a positive offset or move the producer earlier.

The same payload object is delivered to every handler, so event payloads should
be treated as immutable. A listener accepts one typed event argument and may
also accept one or more `Float` arguments for its current clock tick length.
Primitive `Float` payloads are reserved for delta time; event classes, enums,
or other distinct Haxe types should be used instead.

An event payload may reserve a field named `entityHandle` of type
`bevy.EntityHandle`.
Additional handler arguments are then treated like a single-entity query:

```haxe
class ViewLoadedEvent {
    public final entityHandle:bevy.EntityHandle;
    public function new(entityHandle) this.entityHandle = entityHandle;
}

class ViewSystem extends bevy.System {
    @:event
    @:exclude(Sleeping)
    function onViewLoaded(
        event:ViewLoadedEvent,
        position:Position,
        inventory:Inventory,
        entity:bevy.Entity
    ):Void {}
}
```

Component IDs are resolved once when the system activates. For each event, the
generated typed callback reads `event.entityHandle`, verifies that it is still live,
checks every required and excluded component, fetches the requested values, and
only then invokes the method. `Entity` and `Float` arguments inject the selected
entity and the system's current delta time. Optional component arguments do not
filter delivery and receive `null` when absent. Events emitted with offset `0`
perform a liveness check. Events emitted with a positive tick offset additionally
compare the handle's captured generation at the start of dispatch, before any
component checks or fetches.

## System error isolation

Each `SystemList` catches exceptions around each child update, records the
failure on the world, and continues with later systems:

```haxe
world.update(dt); // dt is optional; wall-clock elapsed time is used if omitted

if (world.hasUpdateErrors) {
    for (failure in world.updateErrors) {
        trace('`${failure.systemName}` failed in `${failure.systemListName}`');
        trace('${failure.error}\n${failure.error.stack}');
        trace('frame dt=${failure.deltaTime}, list step=${failure.step}');
    }
}
```

`updateErrors` is cleared at the beginning of every `world.update()`. Errors in
nested or fixed-rate lists report the immediate list name and both the delta
received by that list and the actual clock step supplied to the system.

## System lifetimes

Every activation creates a fresh cleanup scope. Use it for subscriptions and
objects owned by that activation; cleanup runs in reverse registration order:

```haxe
override function onActivate() {
    projectionSub = lifetime.own(
        cameraProps.projType.subscribe(updateProjection),
        subscription -> subscription.unsubscribe()
    );
    lifetime.defer(() -> cameraController?.remove());
}

override function onStop(reason:bevy.SystemStopReason) {
    trace('system stopped because of $reason');
}
```

Stop reasons distinguish `Removed`, `ParentStopped`, `WorldClosing`,
`Reparented`, and `ActivationFailed(error)`. Cleanup still completes if a hook
or another cleanup fails, and activation failure rolls back list attachment.
The zero-argument `onDeactivate()` remains as a migration hook.

External owners can use `observeLifecycle(callback)`, which returns a removable
`SystemLifecycleSubscription`. Lifecycle observation is intentionally separate
from system-owned cleanup so callbacks do not accumulate across activations.
