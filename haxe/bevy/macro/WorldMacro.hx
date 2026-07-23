package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import bevy.macro.ComponentTypeRegistry.RegisteredComponent;

class WorldMacro {
    public static function add(world:Expr, entity:Expr, component:Expr):Expr {
        final info = componentFromValue(component);
        final id = registration(world, info);
        return macro {
            final __bevyComponent = $component;
            $world.insertDynamic($entity, $id, __bevyComponent);
            __bevyComponent;
        };
    }

    public static function addIfMissing(world:Expr, entity:Expr, component:Expr):Expr {
        final info = componentFromValue(component);
        final id = registration(world, info);
        return macro {
            if (!$world.hasDynamic($entity, $id)) {
                final __bevyComponent = $component;
                $world.insertDynamic($entity, $id, __bevyComponent);
            }
        };
    }

    public static function get(world:Expr, entity:Expr, componentType:Expr):Expr {
        final info = componentFromTypeExpr(componentType);
        final id = registration(world, info);
        final type = info.complexType;
        return macro (cast $world.getDynamic($entity, $id) : Null<$type>);
    }

    public static function has(world:Expr, entity:Expr, componentType:Expr):Expr {
        final info = componentFromTypeExpr(componentType);
        return macro $world.hasDynamic($entity, ${registration(world, info)});
    }

    public static function remove(world:Expr, entity:Expr, componentType:Expr):Expr {
        final info = componentFromTypeExpr(componentType);
        return macro $world.removeDynamic($entity, ${registration(world, info)});
    }

    public static function each(world:Expr, requiredExpr:Expr, callback:Expr, excludedExpr:Null<Expr>):Expr {
        final required = componentList(requiredExpr);
        final excluded = isNullExpr(excludedExpr) ? [] : componentList(cast excludedExpr);
        final requiredIds = required.map(info -> registration(world, info));
        final excludedIds = excluded.map(info -> registration(world, info));
        final requiredAssignments = [for (i in 0...requiredIds.length) macro __bevyRequired[$v{i}] = ${requiredIds[i]}];
        final excludedAssignments = [for (i in 0...excludedIds.length) macro __bevyExcluded[$v{i}] = ${excludedIds[i]}];

        final callArgs:Array<Expr> = [macro __bevyEntity];
        for (i in 0...required.length) {
            final type = required[i].complexType;
            final id = requiredIds[i];
            callArgs.push(macro (cast $world.getDynamic(__bevyEntity, $id) : $type));
        }

        return macro {
            final __bevyRequired = new hl.NativeArray<Int>($v{requiredIds.length});
            $b{requiredAssignments};
            final __bevyExcluded = new hl.NativeArray<Int>($v{excludedIds.length});
            $b{excludedAssignments};
            final __bevyQuery = bevy.Native.query_new(
                $world.nativeHandle,
                __bevyRequired,
                __bevyExcluded
            );
            if (__bevyQuery == null)
                throw "Could not create Bevy query";
            final __bevyQueryLength = bevy.Native.query_len(__bevyQuery);
            for (__bevyIndex in 0...__bevyQueryLength) {
                final __bevyEntity:bevy.Entity = new bevy.Entity(
                    bevy.Native.query_entity_at(__bevyQuery, __bevyIndex)
                );
                $callback($a{callArgs});
            }
            bevy.Native.query_close(__bevyQuery);
        };
    }

    public static function query(world:Expr, requiredExpr:Expr, excludedExpr:Null<Expr>):Expr {
        final required = componentList(requiredExpr);
        final excluded = isNullExpr(excludedExpr) ? [] : componentList(cast excludedExpr);
        final requiredIds = required.map(info -> registration(world, info));
        final excludedIds = excluded.map(info -> registration(world, info));
        final requiredNames = required.map(info -> macro $v{info.name});
        final excludedNames = excluded.map(info -> macro $v{info.name});
        return macro new bevy.QueryBase(
            $world,
            [$a{requiredIds}],
            [$a{requiredNames}],
            [$a{excludedIds}],
            [$a{excludedNames}]
        );
    }

    static function registration(world:Expr, info:RegisteredComponent):Expr {
        return macro $v{info.id};
    }

    static function componentList(expr:Expr):Array<RegisteredComponent> {
        return switch (expr.expr) {
            case EArrayDecl(values): values.map(componentFromTypeExpr);
            default:
                Context.error('Expected an array literal of component types, got `${haxe.macro.ExprTools.toString(expr)}`', expr.pos);
                [];
        }
    }

	static function isNullExpr( expr : Null<Expr> ) : Bool {

		if ( expr == null ) return true;
		return switch expr.expr {
			case EConst( CIdent( "null" ) ): true;
			case EParenthesis( inner ): isNullExpr( inner );
			default: false;
		}
	}

    static function componentFromValue(expr:Expr):RegisteredComponent {
        final type = switch (expr.expr) {
            case ENew(path, _): Context.resolveType(TPath(path), expr.pos);
            case ECheckType(_, complex) | EParenthesis({expr:ECheckType(_, complex)}):
                Context.resolveType(complex, expr.pos);
            default: Context.typeof(expr);
        }
        return componentInfo(type, expr.pos);
    }

    static function componentFromTypeExpr(expr:Expr):RegisteredComponent {
        final printed = fieldChain(expr);
        if (printed == null) {
            Context.error("Expected a component type", expr.pos);
            return componentInfo(Context.getType("Dynamic"), expr.pos);
        }
        try {
            return componentInfo(Context.getType(printed), expr.pos);
        } catch (_:Dynamic) {
            Context.error('Component type not found: $printed', expr.pos);
            return componentInfo(Context.getType("Dynamic"), expr.pos);
        }
    }

    static function componentInfo(type:Type, pos:Position):RegisteredComponent
        return ComponentTypeRegistry.register(type, pos);

    static function fieldChain(expr:Expr):Null<String> {
        return switch (expr.expr) {
            case EConst(CIdent(name)): name;
            case EField(parent, field):
                final prefix = fieldChain(parent);
                prefix == null ? null : '$prefix.$field';
            case EParenthesis(inner): fieldChain(inner);
            default: null;
        }
    }
}
#end
