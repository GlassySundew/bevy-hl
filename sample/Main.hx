import bevy.Entity;
import bevy.Native;
import bevy.SystemList;
import bevy.World;

class Main {
    static function main() {
        trace('Bevy HashLink bridge ABI ${Native.bridge_version()}');

        final chainWorld = new World();
		final sameFrameSystems = new SystemList(chainWorld, "SameFrameChain");
		chainWorld.activeSystems.add(sameFrameSystems);
		final sameFrameSpawn = new SameFrameSpawnSystem(chainWorld);
		final sameFrameRepl = new SameFrameReplSystem(chainWorld);
		final sameFrameObserve = new SameFrameObserveSystem(chainWorld);
		sameFrameSystems
			.add(sameFrameSpawn)
			.add(sameFrameRepl)
			.add(sameFrameObserve);
		chainWorld.update(0.01);
		if (sameFrameObserve.matches != 1 || chainWorld.getQuery([ChainReady]).length != 1)
			throw "Same-frame structural query chain failed";
		chainWorld.close();

		final world = new World();
		final lifecycle = new LifecycleSystem( world );
		final lifecycleEvents : Array<String> = [];
		final lifecycleSubscription = lifecycle.observeLifecycle( event -> lifecycleEvents.push( Std.string( event ) ) );
		lifecycle.activate();
		lifecycle.deactivate();
		if ( lifecycle.log.join( "," ) != "activate,stop:Removed,cleanup-second,cleanup-first"
			|| lifecycleEvents.join( "," ) != "Started,Stopped(Removed)" )
			throw 'System activation lifetime failed: ${lifecycle.log} / $lifecycleEvents';
		lifecycleSubscription.unsubscribe();
		lifecycle.activate();
		lifecycle.deactivate();
		if ( lifecycleEvents.length != 2 || lifecycle.log.length != 8 )
			throw "Lifecycle scope or subscription persisted incorrectly";

		final firstLifecycleList = new SystemList( world, "FirstLifecycleList" );
		final secondLifecycleList = new SystemList( world, "SecondLifecycleList" );
		world.activeSystems.add( firstLifecycleList ).add( secondLifecycleList );
		final nestedLifecycle = new LifecycleSystem( world );
		firstLifecycleList.add( nestedLifecycle );
		secondLifecycleList.add( nestedLifecycle );
		secondLifecycleList.deactivate();
		firstLifecycleList.deactivate();
		if ( nestedLifecycle.log.join( "," ) != "activate,stop:Reparented,cleanup-second,cleanup-first,activate,stop:ParentStopped,cleanup-second,cleanup-first"
			|| nestedLifecycle.lifecycleState != Inactive )
			throw 'Nested or reparented lifecycle failed: ${nestedLifecycle.log}';

		final failingActivation = new FailingActivationSystem( world );
		var activationRejected = false;
		try failingActivation.activate() catch ( _ : haxe.Exception ) activationRejected = true;
		if ( !activationRejected || failingActivation.active || failingActivation.parent != null
			|| failingActivation.log.join( "," ) != "activation-failed,cleanup" )
			throw 'Failed activation was not rolled back: ${failingActivation.log}';
		final config = new GameConfig( 2.5 );
		world.insertResource( IGameConfig, config );
        if ( world.resource( IGameConfig ) != config || world.tryResource( IGameConfig ) != config
            || world.getService( IGameConfig ) != config || !world.hasResource( IGameConfig ) )
			throw "Typed resource storage failed";
		final resourceSystem = new ResourceSystem( world );
		if ( resourceSystem.resourceTypes.length != 1
			|| resourceSystem.resourceTypes[0] != "IGameConfig" )
			throw "System resource metadata was not collected";
		resourceSystem.activate();
		final beforeChainedSpawn = world.activeEntities.length;
		final chainedSpawn = world.spawn().add(
			world,
			new Position( 4, 5 ),
			new Velocity( 6, 7 )
		);
		if ( world.activeEntities.length != beforeChainedSpawn + 1
			|| !world.has( chainedSpawn, Position ) || !world.has( chainedSpawn, Velocity ) )
			throw "Fluent Entity.add evaluated its receiver more than once";
		world.despawn( chainedSpawn );
        final moving = world.spawn();
        final sleeping = world.spawn();
		final movingHandle = world.makeHandle( moving );
		final wrongGeneration : bevy.EntityHandle = { ent : cast moving, gen : movingHandle.gen + 1 };
		if ( !world.isHandleValid( movingHandle ) || world.isHandleValid( wrongGeneration )
			|| world.isHandleValid( null ) )
			throw "World handle validation failed";

        world.add(moving, new Position(1, 2));
        world.add(moving, new Velocity(0.5, -1));
		world.add( moving, ( 3 : PrimitiveFlag ) );
		final primitiveQuery = world.getQuery( [PrimitiveFlag] );
		if ( primitiveQuery.length != 1
			|| ( cast primitiveQuery.componentStorages[0].get( moving ) : PrimitiveFlag ) != 3 )
			throw "Primitive component query failed";

        world.add(sleeping, new Position(10, 20));
        world.add(sleeping, new Velocity(99, 99));
        world.add(sleeping, new Sleeping());

		final inspectedEntities = world.entities();
		final inspectedComponents = world.componentsOf( moving );
		if ( inspectedEntities.length != 2
			|| inspectedComponents.length != 3
			|| !Lambda.exists( inspectedComponents, storage -> storage.componentType == "PrimitiveFlag" )
			|| !Lambda.exists( inspectedComponents, storage -> storage.shortComponentType == "Position" ) )
			throw "World introspection failed";

        // Component objects are owned through native Bevy storage at this point.
        hl.Gc.major();

        final movingQuery = world.getQuery([Position, Velocity], [Sleeping]);
        if (movingQuery.entities.length != 1 || movingQuery.entities[0] != moving)
            throw "Persistent query entity snapshot failed";
        final queriedPosition:Position = movingQuery.componentStorages[0].get(moving);
        if (queriedPosition.x != 1 || moving.id != moving.handle)
            throw "Runtime query component view failed";
        var iterated = 0;
        movingQuery.iterUntyped((entity, components) -> {
            final values:Array<Dynamic> = cast components;
            if (entity != moving || (cast values[1]:Velocity).x != 0.5)
                throw "Untyped query iteration returned incorrect values";
            iterated++;
        });
        if (iterated != 1 || movingQuery.excludeComponentStorage.length != 1)
            throw "Untyped query iteration failed";

        final movement = new MovementSystem(world);
        if (movement.priority != 10)
            throw "System macro did not collect class priority metadata";
        movement.activate();
        if (!movement.active || movement.parent != world.activeSystems)
            throw "System did not attach to the world";
        world.update(1);
		if ( resourceSystem.observedSpeed != 2.5 )
			throw "Automatic system resource injection failed";
		resourceSystem.deactivate();
        movement.deactivate();
        if (movement.updates != 1 || movement.active)
            throw "System activation lifecycle failed";

        final position = world.get(moving, Position);
        if (position == null || position.x != 1.5 || position.y != 1)
            throw 'Unexpected position: $position';
        final sleepingPosition = world.get(sleeping, Position);
        if (sleepingPosition == null || sleepingPosition.x != 10 || sleepingPosition.y != 20)
            throw "System exclusion filter failed";

        if (!world.has(moving, Velocity))
            throw "Velocity should exist";
        if (!world.remove(moving, Velocity) || world.has(moving, Velocity))
            throw "Velocity removal failed";
        if (movingQuery.length != 0)
            throw "Persistent query did not observe a structural change";
        movingQuery.componentStorages[1].add(moving, new Velocity(2, 3), world);
        if (movingQuery.length != 1)
            throw "Runtime component storage add failed";
        movingQuery.componentStorages[1].remove(moving, world);

        final pulses = SystemList.atRate(world, 4, "QuarterSecondPulses");
        final pulse = new PulseSystem(world);
        pulses.add(pulse);
        world.activeSystems.add(pulses);
        world.update(0.6);
        world.update(0.15);
        if (pulse.ticks != 3 || pulse.elapsed != 0.75)
            throw 'Fixed-rate SystemList failed: ${pulse.ticks} ticks, ${pulse.elapsed}s';
        if (world.activeSystems.find(PulseSystem) != pulse)
            throw "Nested system lookup failed";

        final damageEvents = new DamageEventSystem(world);
        pulses.add(damageEvents);
        final immediateDamageEvents = new DamageEventSystem(world);
        immediateDamageEvents.activate();
        final secondDamageEvents = new DamageEventSystem(world);
        secondDamageEvents.activate();
        final damageEmitter = new DamageEventEmitterSystem(world);
        damageEmitter.activate();
        world.send(new DamageEvent(7));
        world.update(0.1);
        if (damageEvents.received != 0)
            throw "A rate-limited event system ran before its clock tick";
        if (immediateDamageEvents.received != 2 || immediateDamageEvents.totalDamage != 10)
            throw "Offset-zero events were not delivered in their emitting tick";
        if (secondDamageEvents.received != 2 || secondDamageEvents.totalDamage != 10)
            throw "A shared typed event channel did not deliver to every reader";
        world.update(0.15);
        if (damageEvents.received != 0)
            throw "An event survived beyond its delivery tick";
        if (immediateDamageEvents.received != 2 || immediateDamageEvents.totalDamage != 10)
            throw "An offset-zero event was delivered more than once";

        world.send(new DamageEvent(11), 1);
        world.update(0.05);
        if (immediateDamageEvents.received != 2)
            throw "An offset-one event was delivered too early";
        world.update(0.05);
        if (immediateDamageEvents.received != 3 || immediateDamageEvents.totalDamage != 21)
            throw "An offset-one event was not delivered on the next tick";

        world.send(new DamageEvent(13), 2);
        world.update(0.05);
        world.update(0.05);
        if (immediateDamageEvents.received != 3)
            throw "An offset-two event was delivered too early";
        world.update(0.05);
        if (immediateDamageEvents.received != 4 || immediateDamageEvents.totalDamage != 34)
            throw "An offset-two event was not delivered on the requested tick";
        if (secondDamageEvents.received != 4 || secondDamageEvents.totalDamage != 34)
            throw "Independent event reader cursors diverged";

        final filteredEvents = new FilteredEventSystem(world);
        filteredEvents.activate();
        final missingPosition = world.spawn();
        final staleEntity = world.spawn();
        final staleHandle = world.makeHandle(staleEntity);
        world.despawn(staleEntity);
        world.send(new EntityEvent(world.makeHandle(moving), 5), 1);
        world.send(new EntityEvent(world.makeHandle(sleeping), 7), 1);
        world.send(new EntityEvent(world.makeHandle(missingPosition), 11), 1);
        world.send(new EntityEvent(staleHandle, 13), 1);
        world.send(new EntityEvent(wrongGeneration, 17), 1);
        world.update(0.01);
        world.update(0.01);
        if (filteredEvents.received != 1 || filteredEvents.value != 5
            || filteredEvents.lastEntity != moving || filteredEvents.lastPosition != world.get(moving, Position))
            throw "Component-filtered entity event dispatch failed";

        final faultList = new SystemList(world, "FaultIsolation");
        final faulting = new FaultingSystem(world);
        final recovery = new RecoverySystem(world);
        faultList.add(faulting).add(recovery);
        world.activeSystems.add(faultList);
        world.update(0.01);
        if (!world.hasUpdateErrors || world.updateErrors.length != 1)
            throw "System error was not captured";
        final systemError = world.updateErrors[0];
        if (systemError.systemName != "FaultingSystem"
            || systemError.systemListName != "FaultIsolation"
            || systemError.deltaTime != 0.01
            || systemError.step != 0.01
            || recovery.updates != 1)
            throw "System error context or isolation was incorrect";
        world.update(0.01);
        if (world.hasUpdateErrors || recovery.updates != 2 || faulting.attempts != 2)
            throw "System errors were not reset on the next update";

        moving.despawn(world);
        if (moving.exists(world))
            throw "Despawned entity is still alive";
		if ( world.isHandleValid( movingHandle ) )
			throw "Despawned handle remained valid";

		if ( world.removeResource( IGameConfig ) != config || world.hasResource( IGameConfig ) )
			throw "Typed resource removal failed";
		final missingResourceSystem = new ResourceSystem( world );
		var missingResourceRejected = false;
		try missingResourceSystem.activate() catch ( error:haxe.Exception ) {
			missingResourceRejected = error.message.indexOf( "IGameConfig" ) >= 0;
		}
		if ( !missingResourceRejected || missingResourceSystem.active
			|| missingResourceSystem.parent != null
			|| world.activeSystems.find( ResourceSystem ) != null )
			throw "Missing automatic resource did not reject system activation";

		final worldClosingSystem = new LifecycleSystem( world );
		worldClosingSystem.activate();
		world.close();
		if ( worldClosingSystem.log.join( "," )
			!= "activate,stop:WorldClosing,cleanup-second,cleanup-first" )
			throw 'World closing lifecycle failed: ${worldClosingSystem.log}';

		// Macro IDs are cached independently in every native world.
		final lateWorld = new World();
		final lateComponent = lateWorld.registerComponent( 10000, "LateRegisteredProbe", false );
		if ( lateWorld.registerComponent( 10000, "LateRegisteredProbe", false ) != lateComponent )
			throw "Integer component registration was not stable";
		final lateEntity = lateWorld.spawn();
		final lateValue = { value: 42 };
		lateWorld.insertDynamic( lateEntity, lateComponent, lateValue );
		final lateQuery = new bevy.QueryBase(
			lateWorld,
			[lateComponent],
			["LateRegisteredProbe"],
			[],
			[]
		);
		if ( lateQuery.length != 1
			|| lateWorld.getDynamic( lateEntity, lateComponent ) != lateValue
			|| lateWorld.componentsOf( lateEntity ).length != 1 )
			throw "Late component registration synchronization failed";
		lateWorld.close();
        trace("Bridge sample passed");
    }
}
