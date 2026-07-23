package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

using StringTools;

private typedef ComponentArg = {
	final index : Int;
	final id : Int;
	final name : String;
	final typeName : String;
	final typeExpr : Expr;
	final optional : Bool;
	final sparse : Bool;
}

private typedef UpdateListener = {
	final field : Field;
	final fn : Function;
	final components : Array<ComponentArg>;
	final entityArgs : Array<Int>;
	final dtArgs : Array<Int>;
	final excludes : Array<Expr>;
}

private typedef OptionalIdBinding = {
	final component : ComponentArg;
	final fieldName : String;
}

private typedef QueryBinding = {
	final listener : UpdateListener;
	final fieldName : String;
	final optionalIds : Array<OptionalIdBinding>;
}

private typedef EventListener = {
	final field : Field;
	final fn : Function;
	final eventIndex : Int;
	final eventId : Int;
	final eventType : ComplexType;
	final hasEntityHandleField : Bool;
	final components : Array<ComponentArg>;
	final entityArgs : Array<Int>;
	final dtArgs : Array<Int>;
	final excludes : Array<ComponentArg>;
}

private typedef ResourceField = {
	final field : Field;
	final typeName : String;
	final type : ComplexType;
}

/** Builds query-backed update listeners from metadata on System subclasses. */
class SystemBuilder {

	public static function build() : Array<Field> {
		final fields = Context.getBuildFields();
		final local = switch Context.getLocalType() {
			case TInst( ref, _ ): ref.get();
			default: return fields;
		}
		if ( local.meta.has( ":bevySkipSystemBuild" ) )
			return fields;

		final listeners : Array<UpdateListener> = [];
		final eventListeners : Array<EventListener> = [];
		final resourceFields : Array<ResourceField> = [];
		for ( field in fields ) {
			if ( hasMetadata( field.meta, "updated" ) ) {
				switch ( field.kind ) {
					case FFun( fn ): listeners.push( parseListener( field, fn ) );
					default: Context.error( "@:update can only be applied to a function", field.pos );
				}
			}
			if ( hasEventMetadata( field.meta ) ) {
				switch ( field.kind ) {
					case FFun( fn ): eventListeners.push( parseEventListener( field, fn ) );
					default: Context.error( "@:event can only be applied to a function", field.pos );
				}
			}
			if ( hasMetadata( field.meta, "resource" ) ) {
				switch ( field.kind ) {
					case FVar( type, _ ):
						if ( type == null )
							Context.error( '@:resource field ${field.name} needs an explicit type', field.pos );
						if ( field.access != null && field.access.indexOf( AStatic ) >= 0 )
							Context.error( '@:resource cannot be used on a static field', field.pos );
						if ( field.access != null && field.access.indexOf( AFinal ) >= 0 )
							Context.error( '@:resource cannot be used on a final field', field.pos );
						resourceFields.push( {
							field : field,
							typeName : TypeTools.toString( Context.resolveType( type, field.pos ) ),
							type : type
						} );
					default: Context.error( "@:resource can only be applied to a variable", field.pos );
				}
			}
		}

		if ( !Lambda.exists( fields, field -> field.name == "new" ) )
			fields.push( makeConstructor() );

		final queryBindings = makeQueryBindings( local, listeners );
		for ( binding in queryBindings ) {
			fields.push( makeQueryField( binding.fieldName ) );
			for ( optional in binding.optionalIds )
				fields.push( makeOptionalIdField( optional.fieldName ) );
		}
		if ( queryBindings.length > 0 )
			fields.push( makeQueryInitialization( queryBindings ) );

		final priority = metadata( local.meta.get(), "priority" );
		if ( priority != null ) {
			if ( priority.params.length != 1 )
				Context.error( "@:priority expects one Int expression", priority.pos );
			fields.push( makeDefaultPriority( priority.params[0] ) );
		}

		fields.push( makeUpdate( listeners, queryBindings ) );
		if ( eventListeners.length > 0 )
			fields.push( makeEventRegistration( eventListeners ) );
		if ( resourceFields.length > 0 ) {
			fields.push( makeResourceInjection( resourceFields ) );
			fields.push( makeResourceMetadata( resourceFields ) );
		}
		return fields;
	}

	static function makeResourceInjection( resources : Array<ResourceField> ) : Field {
		final assignments : Array<Expr> = [macro super.__injectResources__()];
		for ( resource in resources ) {
			final target : Expr = {
				expr : EField( macro this, resource.field.name ),
				pos : resource.field.pos
			};
			final type = resource.type;
			assignments.push( macro $target = ( cast world.resources.requireDynamic( $v{resource.typeName} ) : $type ) );
		}
		return( macro class GeneratedResourceInjection {
			override function __injectResources__() : Void$b{assignments}
		} ).fields[0];
	}

	static function makeResourceMetadata( resources : Array<ResourceField> ) : Field {
		final names = resources.map( resource -> macro $v{resource.typeName} );
		return( macro class GeneratedResourceMetadata {
			override function __resourceTypeNames__() : Array<String>
				return super.__resourceTypeNames__().concat( [$a{names}] );
		} ).fields[0];
	}

	static function parseEventListener( field : Field, fn : Function ) : EventListener {
		final resolvedArgs : Array<Type> = [];
		final valueArgs : Array<Int> = [];
		for ( index => arg in fn.args ) {
			if ( arg.type == null ) {
				Context.error( 'Event listener argument ${arg.name} needs an explicit type', field.pos );
				continue;
			}
			final resolved = Context.resolveType( arg.type, field.pos );
			resolvedArgs[index] = resolved;
			final typeName = TypeTools.toString( resolved );
			if ( typeName == "Float" || isEntityType( resolved ) ) continue;
			valueArgs.push( index );
		}
		final payloadCandidates = valueArgs.length <= 1 ? [] : valueArgs.filter( index ->
			hasEntityHandleEventField( resolvedArgs[index] ) );
		final eventIndex = if ( valueArgs.length == 1 ) valueArgs[0]
		else if ( payloadCandidates.length == 1 ) payloadCandidates[0]
		else -1;
		if ( eventIndex < 0 ) {
			if ( payloadCandidates.length > 1 )
				Context.error( "An @:event listener has multiple arguments with a reserved `entityHandle:EntityHandle` field", field.pos );
			else
				Context.error( "An @:event listener with injected components needs one event argument containing `entityHandle:EntityHandle`", field.pos );
		}
		if ( eventIndex < 0 )
			Context.error( "An @:event listener needs one typed event argument", field.pos );

		final eventResolved = resolvedArgs[eventIndex];
		final components : Array<ComponentArg> = [];
		final entityArgs : Array<Int> = [];
		final dtArgs : Array<Int> = [];
		for ( index => arg in fn.args ) {
			if ( index == eventIndex ) continue;
			final resolved = resolvedArgs[index];
			final typeName = TypeTools.toString( resolved );
			if ( typeName == "Float" ) {
				dtArgs.push( index );
			} else if ( isEntityType( resolved ) ) {
				entityArgs.push( index );
			} else {
				final registered = ComponentTypeRegistry.register( resolved, field.pos );
				components.push( {
					index : index,
					id : registered.id,
					name : arg.name,
					typeName : registered.name,
					typeExpr : typeExpr( resolved, field.pos ),
					optional : arg.opt,
					sparse : registered.sparse
				} );
			}
		}

		final excludes : Array<ComponentArg> = [];
		final excludeMeta = metadata( field.meta, "exclude" );
		if ( excludeMeta != null )
			for ( value in excludeMeta.params ) excludes.push( eventFilterComponent( value ) );
		final eventHasEntityHandle = components.length > 0 || entityArgs.length > 0 || excludes.length > 0 ? hasEntityHandleEventField( eventResolved ) : false;
		if ( !eventHasEntityHandle && ( components.length > 0 || entityArgs.length > 0 || excludes.length > 0 ) )
			Context.error( "Component-filtered @:event handlers require their event type to declare `entityHandle:EntityHandle`", field.pos );

		return {
			field : field,
			fn : fn,
			eventIndex : eventIndex,
			eventId : EventTypeRegistry.register( eventResolved, field.pos ),
			eventType : fn.args[eventIndex].type,
			hasEntityHandleField : eventHasEntityHandle,
			components : components,
			entityArgs : entityArgs,
			dtArgs : dtArgs,
			excludes : excludes
		};
	}

	static function parseListener( field : Field, fn : Function ) : UpdateListener {
		final components : Array<ComponentArg> = [];
		final entityArgs : Array<Int> = [];
		final dtArgs : Array<Int> = [];

		for ( index => arg in fn.args ) {
			if ( arg.type == null ) {
				Context.error( 'System listener argument ${arg.name} needs an explicit type', field.pos );
				continue;
			}
			final resolved = Context.resolveType( arg.type, field.pos );
			final typeName = TypeTools.toString( resolved );
			if ( isEntityType( resolved ) ) {
				entityArgs.push( index );
			} else if ( typeName == "Float" ) {
				dtArgs.push( index );
			} else {
				final registered = ComponentTypeRegistry.register( resolved, field.pos );
				components.push( {
					index : index,
					id : registered.id,
					name : arg.name,
					typeName : registered.name,
					typeExpr : typeExpr( resolved, field.pos ),
					optional : arg.opt,
					sparse : registered.sparse
				} );
			}
		}

		final excludes : Array<Expr> = [];
		final excludeMeta = metadata( field.meta, "exclude" );
		if ( excludeMeta != null )
			for ( value in excludeMeta.params )
				excludes.push( value );

		return {
			field : field,
			fn : fn,
			components : components,
			entityArgs : entityArgs,
			dtArgs : dtArgs,
			excludes : excludes
		};
	}

	static function makeConstructor() : Field {
		return( macro class GeneratedSystemConstructor {
			public function new( world : bevy.World, ?priority : Int ) {
				super( world, priority );
			}
		} ).fields[0];
	}

	static function makeDefaultPriority( value : Expr ) : Field {
		return( macro class GeneratedSystemPriority {
			override function __getDefaultPriority__() : Int return $value;
		} ).fields[0];
	}

	static function makeQueryBindings( local : ClassType, listeners : Array<UpdateListener> ) : Array<QueryBinding> {
		final prefix = ~/[^A-Za-z0-9_]/g.replace( local.module + "_" + local.name, "_" );
		final result : Array<QueryBinding> = [];
		var queryIndex = 0;
		for ( listener in listeners ) {
			if ( !isEntityQuery( listener ) ) continue;
			final fieldName = '__bevyQuery_${prefix}_${queryIndex}';
			final optionalIds : Array<OptionalIdBinding> = [];
			var optionalIndex = 0;
			for ( component in listener.components ) {
				if ( !component.optional ) continue;
				optionalIds.push( {
					component : component,
					fieldName : '__bevyOptional_${prefix}_${queryIndex}_${optionalIndex++}'
				} );
			}
			result.push( { listener : listener, fieldName : fieldName, optionalIds : optionalIds } );
			queryIndex++;
		}
		return result;
	}

	static function makeQueryField( name : String ) : Field {
		return {
			name : name,
			access : [APrivate],
			kind : FVar( macro : bevy.QueryBase, macro null ),
			pos : Context.currentPos()
		};
	}

	static function makeOptionalIdField( name : String ) : Field {
		return {
			name : name,
			access : [APrivate],
			kind : FVar( macro : Int, macro - 1 ),
			pos : Context.currentPos()
		};
	}

	static function makeQueryInitialization( bindings : Array<QueryBinding> ) : Field {
		final body : Array<Expr> = [macro super.__initializeQueries__()];
		for ( binding in bindings ) {
			final queryTarget = fieldExpr( binding.fieldName, binding.listener.field.pos );
			final required = binding.listener.components
				.filter( component -> !component.optional )
				.map( component -> component.typeExpr );
			final excluded = binding.listener.excludes;
			body.push( macro if ( $queryTarget == null )
				$queryTarget = world.getQuery( [$a{required}], [$a{excluded}] ) );
			for ( optional in binding.optionalIds ) {
				final target = fieldExpr( optional.fieldName, optional.component.typeExpr.pos );
				body.push( macro $target = world.registerComponent(
					$v{optional.component.id},
					$v{optional.component.typeName},
					$v{optional.component.sparse}
				) );
			}
		}
		return( macro class GeneratedQueryInitialization {
			override function __initializeQueries__() : Void$b{body}
		} ).fields[0];
	}

	static function makeUpdate( listeners : Array<UpdateListener>, bindings : Array<QueryBinding> ) : Field {
		final body : Array<Expr> = [macro super.__update__( dt )];
		for ( listener in listeners ) {
			final binding = Lambda.find( bindings, candidate -> candidate.listener == listener );
			body.push( emitListener( listener, binding ) );
		}
		body.push( macro __flushDeferred__() );

		final field = ( macro class GeneratedSystemUpdate {
			override function __update__( dt : Float ) : Void$b{body}
		} ).fields[0];
		return field;
	}

	static function makeEventRegistration( listeners : Array<EventListener> ) : Field {
		final registrations : Array<Expr> = [macro super.__registerEventHandlers__()];
		for ( listener in listeners ) {
			final componentIds = listener.components.map( component -> macro world.registerComponent(
				$v{component.id},
				$v{component.typeName},
				$v{component.sparse}
			) );
			final excludedIds = listener.excludes.map( component -> macro world.registerComponent(
				$v{component.id},
				$v{component.typeName},
				$v{component.sparse}
			) );
			final args : Array<Expr> = [];
			for ( index in 0...listener.fn.args.length ) {
				if ( index == listener.eventIndex ) {
					args.push( macro __bevyEventValue );
				} else if ( listener.entityArgs.indexOf( index ) >= 0 ) {
					args.push( macro __bevyEventEntity );
				} else if ( listener.dtArgs.indexOf( index ) >= 0 ) {
					args.push( macro dt );
				} else {
					final componentIndex = Lambda.findIndex( listener.components, component ->
						component.index == index );
					final componentType = listener.fn.args[index].type;
					args.push( macro( cast world.getDynamic(
						__bevyEventEntity,
						__bevyEventComponentIds[$v{componentIndex}]
					) : $componentType ) );
				}
			}
			final type = listener.eventType;
			final callback = if ( !listener.hasEntityHandleField ) {
				macro function ( __bevyEventValue : $type, __bevyCheckGeneration : Bool ) : Void {
					$i{listener.field.name}( $a{args} );
				};
			} else {
				var condition : Expr = macro true;
				for ( index => component in listener.components )
					if ( !component.optional )
						condition = macro $condition
							&& world.hasDynamic( __bevyEventEntity, __bevyEventComponentIds[$v{index}] );
				for ( index => _ in listener.excludes )
					condition = macro $condition
						&& !world.hasDynamic( __bevyEventEntity, __bevyEventExcludedIds[$v{index}] );
				macro function ( __bevyEventValue : $type, __bevyCheckGeneration : Bool ) : Void {
					final __bevyEventEntityHandle = __bevyEventValue.entityHandle;
					if ( __bevyEventEntityHandle != null && __bevyEventEntityHandle.ent != null
						&& ( __bevyCheckGeneration ? world.isHandleValid( __bevyEventEntityHandle ) : world.entityExists( __bevyEventEntityHandle.ent ) ) ) {
						final __bevyEventEntity : bevy.Entity = cast __bevyEventEntityHandle.ent;
						if ( $condition ) $i{listener.field.name}( $a{args} );
					}
				};
			};
			registrations.push( macro {
				final __bevyEventComponentIds : Array<Int> = [$a{componentIds}];
				final __bevyEventExcludedIds : Array<Int> = [$a{excludedIds}];
				final __bevyEventChannel : bevy.EventChannel<$type> = cast world.eventBus.channelUntyped( $v{listener.eventId} );
				__addEventSubscription__( new bevy.EventSubscription<$type>(
					__bevyEventChannel,
					$callback
				) );
			} );
		}
		return( macro class GeneratedEventRegistration {
			override function __registerEventHandlers__() : Void$b{registrations}
		} ).fields[0];
	}

	static function emitListener( listener : UpdateListener, binding : Null<QueryBinding> ) : Expr {
		if ( binding == null ) {
			final directArgs : Array<Expr> = [for ( _ in listener.fn.args ) macro dt];
			return macro $i{listener.field.name}( $a{directArgs} );
		}

		final values : Map<Int, Expr> = [];
		var requiredIndex = 0;
		for ( component in listener.components ) {
			values[component.index] = if ( component.optional ) {
				final optional = Lambda.find( binding.optionalIds, value ->
					value.component == component );
				final optionalId = fieldExpr( optional.fieldName, listener.field.pos );
				final type = listener.fn.args[component.index].type;
				macro( cast world.getDynamic( __bevySystemEntity, $optionalId ) : $type );
			} else {
				final storageIndex = requiredIndex++;
				final type = listener.fn.args[component.index].type;
				macro( cast __bevySystemQuery.snapshotValueAt( $v{storageIndex} ) : $type );
			}
		}
		for ( index in listener.entityArgs )
			values[index] = macro __bevySystemEntity;
		for ( index in listener.dtArgs )
			values[index] = macro dt;

		final callArgs : Array<Expr> = [];
		for ( index in 0...listener.fn.args.length )
			callArgs.push( cast values[index] );

		final query = fieldExpr( binding.fieldName, listener.field.pos );
		return macro {
			final __bevySystemQuery : bevy.QueryBase = $query;
			__bevySystemQuery.refresh();
			final __bevySystemQueryLength = __bevySystemQuery.snapshotLength();
			for ( __bevySystemIndex in 0...__bevySystemQueryLength ) {
				final __bevySystemEntity = __bevySystemQuery.snapshotFillAt( __bevySystemIndex );
				$i{listener.field.name}( $a{callArgs} );
			}
		};
	}

	static function isEntityQuery( listener : UpdateListener ) : Bool {
		return listener.components.length > 0
			|| listener.entityArgs.length > 0
			|| listener.excludes.length > 0;
	}

	static function fieldExpr( name : String, pos : Position ) : Expr {
		return { expr : EField( macro this, name ), pos : pos };
	}

	static function hasSparseMetadata( type : Type ) : Bool {
		return switch ( type ) {
			case TInst( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TEnum( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TAbstract( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" );
			case TType( ref, _ ):
				ref.get().meta.has( ":bevySparseSet" )
				|| hasSparseMetadata( Context.follow( type ) );
			default: false;
		}
	}

	static function hasMetadata( entries : Metadata, search : String ) : Bool
		return metadata( entries, search ) != null;

	static function hasEventMetadata( entries : Metadata ) : Bool {
		for ( entry in entries ) {
			var name = entry.name;
			if ( name.startsWith( ":" ) ) name = name.substr( 1 );
			if ( name.startsWith( "bevy_" ) ) name = name.substr( "bevy_".length );
			name = name.toLowerCase().replace( "_", "" );
			if ( name == "event" || name == "onevent" || name == "message" )
				return true;
		}
		return false;
	}

	static function metadata( entries : Metadata, search : String ) : Null<MetadataEntry> {
		for ( entry in entries ) {
			var name = entry.name;
			if ( name.startsWith( ":" ) ) name = name.substr( 1 );
			if ( name.startsWith( "bevy_" ) ) name = name.substr( "bevy_".length );
			if ( name.startsWith( "echoes_" ) ) name = name.substr( "echoes_".length );
			if ( name.length > 0 && search.startsWith( name ) )
				return entry;
		}
		return null;
	}

	static function pathExpr( name : String, pos : Position ) : Expr {
		final parts = name.split( "." );
		var result : Expr = { expr : EConst( CIdent( parts.shift() ) ), pos : pos };
		for ( part in parts )
			result = { expr : EField( result, part ), pos : pos };
		return result;
	}

	/** Accepts bevy.Entity through compatibility typedefs such as ecs.Entity. */
	static function isEntityType( type : Type ) : Bool {
		if ( TypeTools.toString( type ) == "bevy.Entity" )
			return true;
		return TypeTools.toString( Context.follow( type ) ) == "bevy.Entity";
	}

	static function hasEntityHandleEventField( type : Type ) : Bool {
		return switch ( Context.follow( type ) ) {
			case TInst( ref, params ):
				final cls = ref.get();
				final entityHandle = Lambda.find( cls.fields.get(), field ->
					field.name == "entityHandle" );
				if ( entityHandle != null )
					isEntityHandleType( TypeTools.applyTypeParameters( entityHandle.type, cls.params, params ) );
				else if ( cls.superClass != null )
					hasEntityHandleEventField( TInst( cls.superClass.t, cls.superClass.params ) );
				else false;
			case TAnonymous( ref ):
				final entityHandle = Lambda.find( ref.get().fields, field ->
					field.name == "entityHandle" );
				entityHandle != null && isEntityHandleType( entityHandle.type );
			default: false;
		}
	}

	static function isEntityHandleType( type : Type ) : Bool {
		if ( TypeTools.toString( type ) == "bevy.EntityHandle" ) return true;
		return TypeTools.toString( Context.follow( type ) ) == "bevy.EntityHandle";
	}

	static function eventFilterComponent( expr : Expr ) : ComponentArg {
		final name = eventTypePath( expr );
		if ( name == null ) {
			Context.error( "Expected an excluded component type", expr.pos );
			return null;
		}
		final type = try Context.getType( name ) catch( _ : Dynamic ) {
			Context.error( 'Component type not found: $name', expr.pos );
			Context.getType( "Dynamic" );
		};
		final registered = ComponentTypeRegistry.register( type, expr.pos );
		return {
			index : -1,
			id : registered.id,
			name : name,
			typeName : registered.name,
			typeExpr : expr,
			optional : false,
			sparse : registered.sparse
		};
	}

	static function eventTypePath( expr : Expr ) : Null<String> {
		return switch ( expr.expr ) {
			case EConst( CIdent( name ) ): name;
			case EField( owner, field ):
				final prefix = eventTypePath( owner );
				prefix == null ? null : prefix + "." + field;
			case EParenthesis( inner ): eventTypePath( inner );
			default: null;
		}
	}

	static function typeExpr( type : Type, pos : Position ) : Expr {

		final complex = TypeTools.toComplexType( type );
		if ( complex == null ) {
			Context.error( 'Unsupported system component type ${TypeTools.toString( type )}', pos );
			return macro Dynamic;
		}
		return switch complex {
			case TPath( path ):
				final parts = path.pack.concat( [path.name] );
				if ( path.sub != null ) parts.push( path.sub );
				pathExpr( parts.join( "." ), pos );
			default:
				Context.error( 'System component type must have a type path', pos );
				macro Dynamic;
		}
	}
}
#end
